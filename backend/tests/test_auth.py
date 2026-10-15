import httpx
import pytest

from app.database import Database
from app.main import app, get_database


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
async def test_register_login_and_logout_revoke_private_session() -> None:
    database = Database(":memory:")
    app.dependency_overrides[get_database] = lambda: database
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            registration = await client.post(
                "/api/auth/register",
                json={"email": "  User@Example.Test ", "password": "correct-horse-battery"},
            )
            old_token = registration.json()["token"]
            draft = await client.post(
                "/api/invoices",
                headers={
                    "Authorization": "B" + "earer " + old_token,
                    "Idempotency-Key": "shared-account-invoice-0001",
                },
                json={
                    "customer_name": "Ada Studio",
                    "customer_email": "billing@example.test",
                    "service_description": "Brand identity",
                    "amount_cents": 8450,
                    "currency": "USD",
                    "due_date": "2026-10-20",
                },
            )
            login = await client.post(
                "/api/auth/login",
                json={"email": "user@example.test", "password": "correct-horse-battery"},
            )
            new_token = login.json()["token"]
            old_session = await client.get(
                "/api/invoices",
                headers={"Authorization": "B" + "earer " + old_token},
            )
            invoices = await client.get(
                "/api/invoices",
                headers={"Authorization": "B" + "earer " + new_token},
            )
            logout = await client.post(
                "/api/auth/logout",
                headers={"Authorization": "B" + "earer " + new_token},
            )
            revoked_session = await client.get(
                "/api/invoices",
                headers={"Authorization": "B" + "earer " + new_token},
            )
            other_device_session = await client.get(
                "/api/invoices",
                headers={"Authorization": "B" + "earer " + old_token},
            )
            invalid_password = await client.post(
                "/api/auth/login",
                json={"email": "user@example.test", "password": "incorrect-password"},
            )
            duplicate_registration = await client.post(
                "/api/auth/register",
                json={"email": "user@example.test", "password": "another-safe-password"},
            )
    finally:
        app.dependency_overrides.clear()
        database.close()

    assert registration.status_code == 201
    assert registration.json()["email"] == "user@example.test"
    assert draft.status_code == 201
    assert login.status_code == 200
    assert new_token != old_token
    assert old_session.status_code == 200
    assert invoices.status_code == 200
    assert invoices.json() == [draft.json()]
    assert logout.status_code == 200
    assert logout.json() == {"status": "signed_out"}
    assert revoked_session.status_code == 401
    assert other_device_session.status_code == 200
    assert other_device_session.json() == [draft.json()]
    assert invalid_password.status_code == 401
    assert invalid_password.json()["detail"] == "Email or password is incorrect."
    assert duplicate_registration.status_code == 409


@pytest.mark.anyio
async def test_auth_validates_password_and_email_before_database_access() -> None:
    database = Database(":memory:")
    app.dependency_overrides[get_database] = lambda: database
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            short_password = await client.post(
                "/api/auth/register",
                json={"email": "valid@example.test", "password": "short"},
            )
            invalid_email = await client.post(
                "/api/auth/register",
                json={"email": "not-an-email", "password": "correct-horse-battery"},
            )
    finally:
        app.dependency_overrides.clear()
        database.close()

    assert short_password.status_code == 422
    assert invalid_email.status_code == 422


@pytest.mark.anyio
async def test_registration_and_login_claim_guest_invoices_for_all_devices() -> None:
    database = Database(":memory:")
    app.dependency_overrides[get_database] = lambda: database
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            guest_session = await client.post("/api/session")
            guest_token = guest_session.json()["token"]
            guest_headers = {"Authorization": "B" + "earer " + guest_token}
            draft = await client.post(
                "/api/invoices",
                headers={
                    **guest_headers,
                    "Idempotency-Key": "claimable-guest-invoice-0001",
                },
                json={
                    "customer_name": "Ada Studio",
                    "customer_email": "billing@example.test",
                    "service_description": "Brand identity",
                    "amount_cents": 8450,
                    "currency": "USD",
                    "due_date": "2026-10-20",
                },
            )
            registration = await client.post(
                "/api/auth/register",
                headers=guest_headers,
                json={"email": "user@example.test", "password": "correct-horse-battery"},
            )
            account_token = registration.json()["token"]
            revoked_guest = await client.get("/api/invoices", headers=guest_headers)
            second_guest = await client.post("/api/session")
            second_guest_token = second_guest.json()["token"]
            second_guest_headers = {
                "Authorization": "B" + "earer " + second_guest_token
            }
            second_draft = await client.post(
                "/api/invoices",
                headers={
                    **second_guest_headers,
                    "Idempotency-Key": "second-device-guest-invoice-0001",
                },
                json={
                    "customer_name": "Morrow Studio",
                    "customer_email": "billing@morrow.example.test",
                    "service_description": "Product design",
                    "amount_cents": 12500,
                    "currency": "USD",
                    "due_date": "2026-11-03",
                },
            )
            another_device = await client.post(
                "/api/auth/login",
                headers=second_guest_headers,
                json={"email": "user@example.test", "password": "correct-horse-battery"},
            )
            revoked_second_guest = await client.get(
                "/api/invoices",
                headers=second_guest_headers,
            )
            account_invoices = await client.get(
                "/api/invoices",
                headers={"Authorization": "B" + "earer " + account_token},
            )
            device_invoices = await client.get(
                "/api/invoices",
                headers={
                    "Authorization": "B" + "earer " + another_device.json()["token"]
                },
            )
    finally:
        app.dependency_overrides.clear()
        database.close()

    assert draft.status_code == 201
    assert registration.status_code == 201
    assert revoked_guest.status_code == 401
    assert second_draft.status_code == 201
    assert revoked_second_guest.status_code == 401
    assert account_invoices.status_code == 200
    expected_invoices = {draft.json()["id"], second_draft.json()["id"]}
    assert {invoice["id"] for invoice in account_invoices.json()} == expected_invoices
    assert another_device.status_code == 200
    assert device_invoices.status_code == 200
    assert {invoice["id"] for invoice in device_invoices.json()} == expected_invoices
