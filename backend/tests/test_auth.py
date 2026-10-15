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
    assert login.status_code == 200
    assert new_token != old_token
    assert old_session.status_code == 401
    assert invoices.status_code == 200
    assert invoices.json() == []
    assert logout.status_code == 200
    assert logout.json() == {"status": "signed_out"}
    assert revoked_session.status_code == 401
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
