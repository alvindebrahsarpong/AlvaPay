import httpx
import pytest

from app.main import app, get_database


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


@pytest.mark.anyio
async def test_health_reports_api_ready() -> None:
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://testserver",
    ) as client:
        response = await client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "alvapay-api"}


@pytest.mark.anyio
async def test_unknown_route_does_not_return_success() -> None:
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://testserver",
    ) as client:
        response = await client.get("/api/not-a-route")

    assert response.status_code == 404


@pytest.mark.anyio
async def test_required_cloud_database_blocks_startup_without_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("ALVAPAY_REQUIRE_TURSO", "true")
    monkeypatch.delenv("TURSO_DATABASE_URL", raising=False)
    monkeypatch.delenv("TURSO_AUTH_TOKEN", raising=False)
    get_database.cache_clear()

    try:
        with pytest.raises(RuntimeError, match="Cloud storage is required"):
            async with app.router.lifespan_context(app):
                pytest.fail("Application startup unexpectedly succeeded without cloud credentials.")
    finally:
        get_database.cache_clear()
