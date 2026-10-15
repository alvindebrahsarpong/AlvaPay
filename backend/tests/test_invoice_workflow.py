import json
from typing import Any

import httpx
import pytest

from app.database import Database
from app.main import app, get_database, get_paypal_service
from app.paypal import PayPalService


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def _invoice_payload() -> dict[str, Any]:
    return {
        "customer_name": "Ada Studio",
        "customer_email": "billing@example.test",
        "service_description": "Brand identity",
        "amount_cents": 8450,
        "currency": "USD",
        "due_date": "2026-10-20",
    }


def _remote_order(
    *,
    status: str,
    purchase_unit: dict[str, Any],
) -> dict[str, Any]:
    unit = dict(purchase_unit)
    if status == "COMPLETED":
        unit["payments"] = {
            "captures": [
                {
                    "id": "CAPTURE-1",
                    "status": "COMPLETED",
                    "amount": {"currency_code": "USD", "value": "84.50"},
                }
            ]
        }
    return {"id": "ORDER-1", "status": status, "purchase_units": [unit]}


@pytest.mark.anyio
async def test_invoice_checkout_capture_is_idempotent_and_verified() -> None:
    database = Database(":memory:")
    order_status = "CREATED"
    purchase_unit: dict[str, Any] = {}
    create_calls = 0
    capture_calls = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal create_calls, capture_calls, purchase_unit, order_status
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(
                200,
                json={"access_token": "synthetic-token", "expires_in": 3600},
            )
        if request.method == "POST" and request.url.path == "/v2/checkout/orders":
            create_calls += 1
            body = json.loads(request.content)
            purchase_unit = body["purchase_units"][0]
            return httpx.Response(
                201,
                json={
                    "id": "ORDER-1",
                    "status": "PAYER_ACTION_REQUIRED",
                    "links": [
                        {
                            "rel": "payer-action",
                            "href": "https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1",
                        }
                    ],
                },
            )
        if request.method == "GET" and request.url.path == "/v2/checkout/orders/ORDER-1":
            return httpx.Response(
                200, json=_remote_order(status=order_status, purchase_unit=purchase_unit)
            )
        if request.method == "POST" and request.url.path == "/v2/checkout/orders/ORDER-1/capture":
            capture_calls += 1
            order_status = "COMPLETED"
            return httpx.Response(
                201,
                json=_remote_order(status="COMPLETED", purchase_unit=purchase_unit),
            )
        raise AssertionError(f"Unexpected PayPal request: {request.method} {request.url.path}")

    paypal = PayPalService(
        client_id="synthetic-client-id",
        client_secret="synthetic-client-secret",
        transport=httpx.MockTransport(handler),
    )
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_paypal_service] = lambda: paypal
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            session = await client.post("/api/session")
            token = session.json()["token"]
            headers = {"Authorization": f"Bearer {token}"}

            created = await client.post(
                "/api/invoices",
                json=_invoice_payload(),
                headers={
                    **headers,
                    "Idempotency-Key": "checkout-workflow-invoice-0001",
                },
            )
            retried_create = await client.post(
                "/api/invoices",
                json=_invoice_payload(),
                headers={
                    **headers,
                    "Idempotency-Key": "checkout-workflow-invoice-0001",
                },
            )
            conflicting_create = await client.post(
                "/api/invoices",
                json={**_invoice_payload(), "amount_cents": 9000},
                headers={
                    **headers,
                    "Idempotency-Key": "checkout-workflow-invoice-0001",
                },
            )
            invoice_id = created.json()["id"]
            unconfirmed_checkout = await client.post(
                f"/api/invoices/{invoice_id}/checkout",
                headers=headers,
            )
            mismatched_confirmation = await client.post(
                f"/api/invoices/{invoice_id}/checkout",
                json={"confirmed": True, "amount_cents": 9000, "currency": "USD"},
                headers=headers,
            )
            confirmation = {"confirmed": True, "amount_cents": 8450, "currency": "USD"}
            first_checkout = await client.post(
                f"/api/invoices/{invoice_id}/checkout",
                json=confirmation,
                headers=headers,
            )
            retry_checkout = await client.post(
                f"/api/invoices/{invoice_id}/checkout",
                json=confirmation,
                headers=headers,
            )
            not_approved = await client.post(
                f"/api/invoices/{invoice_id}/capture",
                json={"status": "COMPLETED"},
                headers=headers,
            )
            order_status = "APPROVED"
            captured = await client.post(
                f"/api/invoices/{invoice_id}/capture",
                headers=headers,
            )
            duplicate_capture = await client.post(
                f"/api/invoices/{invoice_id}/capture",
                headers=headers,
            )
            final_invoice = await client.get(
                f"/api/invoices/{invoice_id}",
                headers=headers,
            )
    finally:
        app.dependency_overrides.clear()
        await paypal.close()
        database.close()

    assert session.status_code == 201
    assert created.status_code == 201
    assert retried_create.json()["id"] == created.json()["id"]
    assert conflicting_create.status_code == 409
    assert created.json()["status"] == "DRAFT"
    assert unconfirmed_checkout.status_code == 422
    assert mismatched_confirmation.status_code == 409
    assert first_checkout.status_code == retry_checkout.status_code == 200
    assert first_checkout.json()["status"] == "CHECKOUT_PENDING"
    assert first_checkout.json()["approval_url"].startswith("https://www.sandbox.paypal.com/")
    assert not_approved.status_code == 409
    assert capture_calls == 1
    assert captured.status_code == 200
    assert captured.json()["status"] == "PAID"
    assert captured.json()["paypal_capture_id"] == "CAPTURE-1"
    assert duplicate_capture.json()["status"] == "PAID"
    assert final_invoice.json()["status"] == "PAID"
    assert create_calls == 1


@pytest.mark.anyio
async def test_invoice_payment_status_is_private_and_unverified_amount_is_not_paid() -> None:
    database = Database(":memory:")
    purchase_unit: dict[str, Any] = {}
    order_status = "CREATED"
    capture_calls = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal purchase_unit, capture_calls
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(
                200,
                json={"access_token": "synthetic-token", "expires_in": 3600},
            )
        if request.method == "POST" and request.url.path == "/v2/checkout/orders":
            purchase_unit = json.loads(request.content)["purchase_units"][0]
            return httpx.Response(
                201,
                json={
                    "id": "ORDER-1",
                    "status": "PAYER_ACTION_REQUIRED",
                    "links": [
                        {
                            "rel": "payer-action",
                            "href": "https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1",
                        }
                    ],
                },
            )
        if request.method == "GET":
            mismatched = dict(purchase_unit)
            mismatched["amount"] = {"currency_code": "USD", "value": "99.00"}
            return httpx.Response(
                200,
                json=_remote_order(status=order_status, purchase_unit=mismatched),
            )
        if request.method == "POST" and request.url.path.endswith("/capture"):
            capture_calls += 1
            return httpx.Response(201, json={})
        raise AssertionError(f"Unexpected PayPal request: {request.method} {request.url.path}")

    paypal = PayPalService(
        client_id="synthetic-client-id",
        client_secret="synthetic-client-secret",
        transport=httpx.MockTransport(handler),
    )
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_paypal_service] = lambda: paypal
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            first_session = (await client.post("/api/session")).json()["token"]
            second_session = (await client.post("/api/session")).json()["token"]
            first_headers = {"Authorization": f"Bearer {first_session}"}
            second_headers = {"Authorization": f"Bearer {second_session}"}
            unauthorized = await client.get("/api/invoices")
            created = await client.post(
                "/api/invoices",
                json=_invoice_payload(),
                headers={
                    **first_headers,
                    "Idempotency-Key": "private-workflow-invoice-0001",
                },
            )
            invoice_id = created.json()["id"]
            hidden_invoice = await client.get(
                f"/api/invoices/{invoice_id}",
                headers=second_headers,
            )
            await client.post(
                f"/api/invoices/{invoice_id}/checkout",
                json={"confirmed": True, "amount_cents": 8450, "currency": "USD"},
                headers=first_headers,
            )
            unverified = await client.post(
                f"/api/invoices/{invoice_id}/capture",
                headers=first_headers,
            )
            final_invoice = await client.get(
                f"/api/invoices/{invoice_id}",
                headers=first_headers,
            )
    finally:
        app.dependency_overrides.clear()
        await paypal.close()
        database.close()

    assert unauthorized.status_code == 401
    assert hidden_invoice.status_code == 404
    assert unverified.status_code == 502
    assert final_invoice.json()["status"] == "CAPTURE_IN_PROGRESS"
    assert capture_calls == 0
