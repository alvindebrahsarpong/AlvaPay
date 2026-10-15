import asyncio
import logging
import os
import time
from dataclasses import dataclass
from typing import Any
from urllib.parse import quote, urlparse

import httpx

logger = logging.getLogger(__name__)

_SANDBOX_API_URL = "https://api-m.sandbox.paypal.com"


class PayPalConfigurationError(Exception):
    pass


class PayPalServiceError(Exception):
    pass


@dataclass(frozen=True)
class CreatedOrder:
    order_id: str
    status: str
    approval_url: str


class PayPalService:
    def __init__(
        self,
        *,
        client_id: str | None = None,
        client_secret: str | None = None,
        environment: str | None = None,
        return_url: str | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.client_id = client_id if client_id is not None else os.getenv("PAYPAL_CLIENT_ID", "")
        self.client_secret = (
            client_secret if client_secret is not None else os.getenv("PAYPAL_CLIENT_SECRET", "")
        )
        self.environment = environment or os.getenv("PAYPAL_ENV", "sandbox")
        self.return_url = return_url or os.getenv("APP_RETURN_URL", "http://localhost:8080/")
        self.transport = transport
        self._client: httpx.AsyncClient | None = None
        self._access_token: str | None = None
        self._token_expires_at = 0.0

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def create_order(
        self,
        *,
        invoice_id: str,
        description: str,
        amount_cents: int,
        currency: str,
        request_id: str,
    ) -> CreatedOrder:
        self._validate_environment()
        payload = {
            "intent": "CAPTURE",
            "purchase_units": [
                {
                    "reference_id": invoice_id,
                    "custom_id": invoice_id,
                    "invoice_id": f"ALVAPAY-{invoice_id}",
                    "description": description[:127],
                    "amount": {
                        "currency_code": currency,
                        "value": _format_amount(amount_cents),
                    },
                }
            ],
            "payment_source": {
                "paypal": {
                    "experience_context": {
                        "brand_name": "AlvaPay",
                        "user_action": "PAY_NOW",
                        "shipping_preference": "NO_SHIPPING",
                        "return_url": self.return_url,
                        "cancel_url": self.return_url,
                    }
                }
            },
        }
        response = await self._api_request(
            "POST",
            "/v2/checkout/orders",
            json=payload,
            request_id=request_id,
        )
        order_id = response.get("id")
        status = response.get("status")
        links = response.get("links", [])
        approval_url = next(
            (
                link.get("href")
                for link in links
                if link.get("rel") == "payer-action" and isinstance(link.get("href"), str)
            ),
            None,
        )
        if not isinstance(order_id, str) or not order_id:
            raise PayPalServiceError("PayPal returned an order without an identifier.")
        if status not in {"CREATED", "PAYER_ACTION_REQUIRED"}:
            raise PayPalServiceError("PayPal did not create an order ready for approval.")
        if not _is_sandbox_approval_url(approval_url):
            raise PayPalServiceError("PayPal did not return a valid Sandbox approval link.")
        return CreatedOrder(order_id, status, approval_url)

    async def get_order(self, order_id: str) -> dict[str, Any]:
        self._validate_environment()
        return await self._api_request(
            "GET",
            f"/v2/checkout/orders/{quote(order_id, safe='')}",
        )

    async def capture_order(self, order_id: str, *, request_id: str) -> dict[str, Any]:
        self._validate_environment()
        return await self._api_request(
            "POST",
            f"/v2/checkout/orders/{quote(order_id, safe='')}/capture",
            json={},
            request_id=request_id,
        )

    def _validate_environment(self) -> None:
        if self.environment != "sandbox":
            raise PayPalConfigurationError(
                "AlvaPay is restricted to PayPal Sandbox credentials and endpoints."
            )
        if not self.client_id or not self.client_secret:
            raise PayPalConfigurationError(
                "PayPal Sandbox is not configured. Add the client ID and "
                "secret to the backend environment."
            )

    async def _api_request(
        self,
        method: str,
        path: str,
        *,
        json: dict[str, Any] | None = None,
        request_id: str | None = None,
    ) -> dict[str, Any]:
        headers: dict[str, str] = {}
        if request_id is not None:
            headers["PayPal-Request-Id"] = request_id

        for attempt in range(3):
            token = await self._get_access_token()
            try:
                response = await self._http_client().request(
                    method,
                    path,
                    headers={**headers, "Authorization": f"Bearer {token}"},
                    json=json,
                )
            except httpx.RequestError as error:
                if attempt < 2:
                    await asyncio.sleep(0.2 * (2**attempt))
                    continue
                logger.warning("PayPal request failed: %s", type(error).__name__)
                raise PayPalServiceError(
                    "PayPal Sandbox is temporarily unreachable. Please try again."
                ) from error

            if (response.status_code == 429 or response.status_code >= 500) and attempt < 2:
                await asyncio.sleep(0.2 * (2**attempt))
                continue
            if response.is_error:
                logger.warning("PayPal request returned HTTP %s", response.status_code)
                raise PayPalServiceError(
                    "PayPal could not complete this request. Check the invoice and try again."
                )
            try:
                result = response.json()
            except ValueError as error:
                raise PayPalServiceError("PayPal returned an unreadable response.") from error
            if not isinstance(result, dict):
                raise PayPalServiceError("PayPal returned an invalid response.")
            return result

        raise PayPalServiceError("PayPal Sandbox is temporarily unavailable. Please try again.")

    async def _get_access_token(self) -> str:
        if self._access_token and time.monotonic() < self._token_expires_at:
            return self._access_token

        if not self.client_id or not self.client_secret:
            raise PayPalConfigurationError(
                "PayPal Sandbox is not configured. Add the client ID and "
                "secret to the backend environment."
            )
        if self.environment != "sandbox":
            raise PayPalConfigurationError(
                "AlvaPay is restricted to PayPal Sandbox credentials and endpoints."
            )

        for attempt in range(3):
            try:
                response = await self._http_client().post(
                    "/v1/oauth2/token",
                    auth=(self.client_id, self.client_secret),
                    data={"grant_type": "client_credentials"},
                )
            except httpx.RequestError as error:
                if attempt < 2:
                    await asyncio.sleep(0.2 * (2**attempt))
                    continue
                logger.warning("PayPal OAuth request failed: %s", type(error).__name__)
                raise PayPalServiceError(
                    "PayPal Sandbox authentication is temporarily unavailable."
                ) from error

            if (response.status_code == 429 or response.status_code >= 500) and attempt < 2:
                await asyncio.sleep(0.2 * (2**attempt))
                continue
            if response.is_error:
                logger.warning("PayPal OAuth returned HTTP %s", response.status_code)
                raise PayPalServiceError("PayPal Sandbox could not authenticate this app.")
            try:
                token_response = response.json()
                token = token_response["access_token"]
                expires_in = int(token_response["expires_in"])
            except (ValueError, KeyError, TypeError) as error:
                raise PayPalServiceError(
                    "PayPal returned an invalid access token response."
                ) from error
            if not isinstance(token, str) or expires_in <= 0:
                raise PayPalServiceError("PayPal returned an invalid access token response.")

            self._access_token = token
            self._token_expires_at = time.monotonic() + max(expires_in - 60, 1)
            return token

        raise PayPalServiceError("PayPal Sandbox authentication is temporarily unavailable.")

    def _http_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=_SANDBOX_API_URL,
                timeout=httpx.Timeout(20.0),
                transport=self.transport,
            )
        return self._client


def _format_amount(amount_cents: int) -> str:
    return f"{amount_cents // 100}.{amount_cents % 100:02d}"


def _is_sandbox_approval_url(url: object) -> bool:
    if not isinstance(url, str):
        return False
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.hostname == "www.sandbox.paypal.com"
