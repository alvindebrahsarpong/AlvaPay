import json

import httpx
import pytest

from app.paypal import (
    PayPalConfigurationError,
    PayPalService,
    PayPalServiceError,
)


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def _order_response(
    *, approval_url: str = "https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1"
) -> httpx.Response:
    return httpx.Response(
        201,
        json={
            "id": "ORDER-1",
            "status": "PAYER_ACTION_REQUIRED",
            "links": [{"rel": "payer-action", "href": approval_url}],
        },
    )


def _service(transport: httpx.AsyncBaseTransport) -> PayPalService:
    return PayPalService(
        client_id="synthetic-client-id",
        client_secret="synthetic-client-secret",
        transport=transport,
    )


@pytest.mark.anyio
async def test_create_order_uses_capture_intent_and_request_id() -> None:
    requests: list[httpx.Request] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(200, json={"access_token": "synthetic-token", "expires_in": 3600})
        return _order_response()

    service = _service(httpx.MockTransport(handler))
    try:
        order = await service.create_order(
            invoice_id="invoice-1",
            description="Brand identity",
            amount_cents=8450,
            currency="USD",
            request_id="stable-create-key",
        )
    finally:
        await service.close()

    create_request = requests[1]
    create_body = json.loads(create_request.content)
    unit = create_body["purchase_units"][0]
    assert order.order_id == "ORDER-1"
    assert order.approval_url.startswith("https://www.sandbox.paypal.com/")
    assert create_body["intent"] == "CAPTURE"
    assert unit["custom_id"] == "invoice-1"
    assert unit["amount"] == {"currency_code": "USD", "value": "84.50"}
    assert create_body["payment_source"]["paypal"]["experience_context"]["user_action"] == "PAY_NOW"
    assert create_request.headers["PayPal-Request-Id"] == "stable-create-key"


@pytest.mark.anyio
async def test_capture_and_get_use_server_owned_order_id() -> None:
    requests: list[httpx.Request] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={"access_token": "synthetic-token", "expires_in": 3600})

    service = _service(httpx.MockTransport(handler))
    service._access_token = "cached-token"
    service._token_expires_at = 9_999_999_999
    try:
        await service.get_order("ORDER/1")
        await service.capture_order("ORDER-1", request_id="stable-capture-key")
    finally:
        await service.close()

    assert requests[0].url.raw_path == b"/v2/checkout/orders/ORDER%2F1"
    assert requests[1].url.path == "/v2/checkout/orders/ORDER-1/capture"
    assert requests[1].headers["PayPal-Request-Id"] == "stable-capture-key"
    assert json.loads(requests[1].content) == {}


@pytest.mark.anyio
async def test_oauth_token_is_cached_for_following_paypal_requests() -> None:
    oauth_calls = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal oauth_calls
        if request.url.path == "/v1/oauth2/token":
            oauth_calls += 1
            return httpx.Response(
                200,
                json={"access_token": "synthetic-token", "expires_in": 3600},
            )
        return httpx.Response(200, json={"id": "ORDER-1", "status": "CREATED"})

    service = _service(httpx.MockTransport(handler))
    try:
        await service.get_order("ORDER-1")
        await service.get_order("ORDER-1")
    finally:
        await service.close()

    assert oauth_calls == 1


@pytest.mark.anyio
async def test_transient_create_failure_retries_with_the_same_idempotency_key() -> None:
    create_keys: list[str | None] = []
    create_calls = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal create_calls
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(200, json={"access_token": "synthetic-token", "expires_in": 3600})
        create_calls += 1
        create_keys.append(request.headers.get("PayPal-Request-Id"))
        if create_calls == 1:
            return httpx.Response(503, json={"name": "SERVICE_UNAVAILABLE"})
        return _order_response()

    service = _service(httpx.MockTransport(handler))
    try:
        await service.create_order(
            invoice_id="invoice-1",
            description="Brand identity",
            amount_cents=8450,
            currency="USD",
            request_id="same-key-on-retry",
        )
    finally:
        await service.close()

    assert create_calls == 2
    assert create_keys == ["same-key-on-retry", "same-key-on-retry"]


@pytest.mark.anyio
async def test_create_order_rejects_non_sandbox_approval_link() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(200, json={"access_token": "synthetic-token", "expires_in": 3600})
        return _order_response(approval_url="https://www.paypal.com/checkoutnow?token=ORDER-1")

    service = _service(httpx.MockTransport(handler))
    with pytest.raises(PayPalServiceError, match="Sandbox approval link"):
        try:
            await service.create_order(
                invoice_id="invoice-1",
                description="Brand identity",
                amount_cents=8450,
                currency="USD",
                request_id="stable-create-key",
            )
        finally:
            await service.close()


@pytest.mark.anyio
async def test_sandbox_configuration_is_required() -> None:
    service = PayPalService(
        client_id="synthetic-client-id",
        client_secret="synthetic-client-secret",
        environment="live",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(500),
        ),
    )

    with pytest.raises(PayPalConfigurationError, match="restricted to PayPal Sandbox"):
        await service.get_order("ORDER-1")
    await service.close()


@pytest.mark.anyio
async def test_missing_credentials_fail_before_any_external_request() -> None:
    request_count = 0

    async def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        return httpx.Response(200, json={})

    service = PayPalService(
        client_id="",
        client_secret="",
        transport=httpx.MockTransport(handler),
    )
    with pytest.raises(PayPalConfigurationError, match="not configured"):
        await service.get_order("ORDER-1")
    await service.close()

    assert request_count == 0


@pytest.mark.anyio
async def test_paypal_client_does_not_retry_non_transient_order_errors() -> None:
    create_calls = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal create_calls
        if request.url.path == "/v1/oauth2/token":
            return httpx.Response(200, json={"access_token": "synthetic-token", "expires_in": 3600})
        create_calls += 1
        return httpx.Response(422, json={"name": "UNPROCESSABLE_ENTITY"})

    service = _service(httpx.MockTransport(handler))
    with pytest.raises(PayPalServiceError, match="could not complete this request"):
        try:
            await service.create_order(
                invoice_id="invoice-1",
                description="Brand identity",
                amount_cents=8450,
                currency="USD",
                request_id="stable-create-key",
            )
        finally:
            await service.close()

    assert create_calls == 1
