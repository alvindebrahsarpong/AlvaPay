import json
from typing import Any

import httpx
import pytest

from app.ai import InvoiceDraftService
from app.database import Database
from app.main import app, get_database, get_invoice_draft_service
from app.schemas import CashFlowCurrencyTotal, InvoiceCreateRequest


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def _invoice_request(amount_cents: int, currency: str) -> InvoiceCreateRequest:
    return InvoiceCreateRequest(
        customer_name="Synthetic Studio",
        customer_email="billing@example.test",
        service_description="Synthetic design services",
        amount_cents=amount_cents,
        currency=currency,
        due_date="2026-10-20",
    )


def _mark_paid(
    database: Database,
    *,
    owner_id: str,
    amount_cents: int,
    currency: str,
    id_suffix: str,
) -> None:
    invoice = database.create_invoice(
        _invoice_request(amount_cents, currency),
        owner_id=owner_id,
        idempotency_key=f"cash-flow-paid-{id_suffix}-0001",
    )
    invoice_id = str(invoice["id"])
    database.begin_checkout(invoice_id, owner_id=owner_id)
    database.save_order(
        invoice_id,
        owner_id=owner_id,
        order_id=f"ORDER-{id_suffix}",
        approval_url=(
            "https://www.sandbox.paypal.com/checkoutnow?token="
            f"ORDER-{id_suffix}"
        ),
    )
    database.begin_capture(invoice_id, owner_id=owner_id)
    database.mark_paid(
        invoice_id,
        owner_id=owner_id,
        capture_id=f"CAPTURE-{id_suffix}",
    )


@pytest.mark.anyio
async def test_summary_uses_only_owner_scoped_verified_payment_aggregates() -> None:
    database = Database(":memory:")
    token = database.create_session()
    owner_id = database.owner_for_token(token)
    other_owner_id = database.owner_for_token(database.create_session())
    assert owner_id is not None and other_owner_id is not None
    _mark_paid(
        database,
        owner_id=owner_id,
        amount_cents=8450,
        currency="USD",
        id_suffix="owner-usd",
    )
    _mark_paid(
        database,
        owner_id=owner_id,
        amount_cents=2500,
        currency="EUR",
        id_suffix="owner-eur",
    )
    _mark_paid(
        database,
        owner_id=other_owner_id,
        amount_cents=99000,
        currency="USD",
        id_suffix="other-owner",
    )
    database.create_invoice(
        _invoice_request(40000, "USD"),
        owner_id=owner_id,
        idempotency_key="cash-flow-unpaid-invoice-0001",
    )

    sent_payloads: list[dict[str, Any]] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        sent_payloads.append(body)
        return httpx.Response(
            200,
            json={
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(
                            {"summary": "Verified receipts are grouped by currency."}
                        ),
                    }
                ]
            },
        )

    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_invoice_draft_service] = lambda: InvoiceDraftService(
        api_key="synthetic-test-key",
        transport=httpx.MockTransport(handler),
    )
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            response = await client.post(
                "/api/ai/cash-flow-summary",
                headers={"Authorization": "B" + "earer " + token},
            )
    finally:
        app.dependency_overrides.clear()
        database.close()

    assert response.status_code == 200, response.text
    assert response.json() == {
        "verified_invoice_count": 2,
        "totals_by_currency": [
            {
                "currency": "EUR",
                "paid_invoice_count": 1,
                "received_cents": 2500,
            },
            {
                "currency": "USD",
                "paid_invoice_count": 1,
                "received_cents": 8450,
            },
        ],
        "summary": "Verified receipts are grouped by currency.",
    }
    request_body = sent_payloads[0]
    user_content = request_body["messages"][0]["content"]
    assert request_body["output_config"]["format"]["type"] == "json_schema"
    assert json.loads(user_content) == {
        "verified_payments_by_currency": [
            {"currency": "EUR", "paid_invoice_count": 1, "received_cents": 2500},
            {"currency": "USD", "paid_invoice_count": 1, "received_cents": 8450},
        ]
    }
    assert "Synthetic Studio" not in user_content
    assert "40000" not in user_content
    assert "99000" not in user_content


@pytest.mark.anyio
async def test_empty_verified_history_does_not_call_ai_provider() -> None:
    database = Database(":memory:")
    token = database.create_session()
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_invoice_draft_service] = lambda: InvoiceDraftService(
        api_key=""
    )
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            response = await client.post(
                "/api/ai/cash-flow-summary",
                headers={"Authorization": "B" + "earer " + token},
            )
    finally:
        app.dependency_overrides.clear()
        database.close()

    assert response.status_code == 200, response.text
    assert response.json() == {
        "verified_invoice_count": 0,
        "totals_by_currency": [],
        "summary": "No verified payments are recorded yet.",
    }


@pytest.mark.anyio
async def test_ai_cash_flow_summary_retries_invalid_structured_output() -> None:
    request_payloads: list[dict[str, Any]] = []
    responses = [
        {"summary": 12},
        {"summary": "One verified payment was recorded."},
    ]

    async def handler(request: httpx.Request) -> httpx.Response:
        request_payloads.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={"content": [{"type": "text", "text": json.dumps(responses.pop(0))}]},
        )

    service = InvoiceDraftService(
        api_key="synthetic-test-key",
        transport=httpx.MockTransport(handler),
    )
    summary = await service.create_cash_flow_summary(
        [
            CashFlowCurrencyTotal(
                currency="USD",
                paid_invoice_count=1,
                received_cents=8450,
            )
        ]
    )

    assert summary.summary == "One verified payment was recorded."
    assert len(request_payloads) == 2
    assert "rejected by validation" in request_payloads[1]["messages"][0]["content"]
    assert "future income" in request_payloads[0]["system"]
    assert request_payloads[0]["output_config"]["format"]["type"] == "json_schema"
