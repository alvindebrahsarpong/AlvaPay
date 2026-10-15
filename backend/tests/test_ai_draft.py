import json
from typing import Any

import httpx
import pytest

from app.ai import AIConfigurationError, AIProviderError, InvoiceDraftService
from app.main import app, get_invoice_draft_service

_VALID_DRAFT = {
    "customer_name": "Ada Studio",
    "customer_email": "billing@example.test",
    "service_description": "Brand identity",
    "amount_cents": 8450,
    "currency": "USD",
    "due_date": "2026-10-20",
}


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def _anthropic_response(draft: dict[str, Any]) -> httpx.Response:
    return httpx.Response(
        200,
        json={"content": [{"type": "text", "text": json.dumps(draft)}]},
    )


@pytest.mark.anyio
async def test_ai_draft_retries_schema_failure_once_with_feedback() -> None:
    sent_messages: list[dict[str, Any]] = []
    responses = [
        _anthropic_response({**_VALID_DRAFT, "currency": "GHS"}),
        _anthropic_response(_VALID_DRAFT),
    ]

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/messages"
        sent_messages.append(json.loads(request.content))
        return responses.pop(0)

    service = InvoiceDraftService(
        api_key="synthetic-test-key",
        model="claude-sonnet-5-5",
        transport=httpx.MockTransport(handler),
    )

    draft = await service.create_draft(
        "Invoice Ada Studio 84.50 USD for brand identity, due October 20."
    )

    assert draft.model_dump() == _VALID_DRAFT
    assert len(sent_messages) == 2
    assert "rejected by validation" in sent_messages[1]["messages"][0]["content"]
    assert sent_messages[0]["output_config"]["format"]["type"] == "json_schema"


@pytest.mark.anyio
async def test_ai_draft_does_not_call_provider_without_configuration() -> None:
    service = InvoiceDraftService(api_key="")

    with pytest.raises(AIConfigurationError, match="not configured"):
        await service.create_draft("Invoice Ada 84.50 USD for design work.")


@pytest.mark.anyio
async def test_ai_provider_failure_returns_friendly_error() -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, json={"error": {"message": "provider internals"}})

    service = InvoiceDraftService(
        api_key="synthetic-test-key",
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(AIProviderError, match="try again shortly"):
        await service.create_draft("Invoice Ada 84.50 USD for design work.")


@pytest.mark.anyio
async def test_parse_endpoint_validates_input_and_returns_draft() -> None:
    async def handler(_request: httpx.Request) -> httpx.Response:
        return _anthropic_response(_VALID_DRAFT)

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
                "/api/ai/draft",
                json={"text": "Invoice Ada 84.50 USD for brand identity."},
            )
            invalid = await client.post("/api/ai/draft", json={"text": "short"})
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == _VALID_DRAFT
    assert invalid.status_code == 422


@pytest.mark.anyio
async def test_parse_endpoint_reports_missing_ai_key_without_fallback() -> None:
    app.dependency_overrides[get_invoice_draft_service] = lambda: InvoiceDraftService(api_key="")
    try:
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://testserver",
        ) as client:
            response = await client.post(
                "/api/ai/draft",
                json={"text": "Invoice Ada 84.50 USD for brand identity."},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["detail"].startswith("AI drafting is not configured")
