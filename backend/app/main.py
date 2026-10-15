import logging
import os
from collections.abc import Mapping
from contextlib import asynccontextmanager
from decimal import Decimal, InvalidOperation
from functools import lru_cache
from pathlib import Path
from typing import Annotated, Any

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.ai import AIConfigurationError, AIProviderError, InvoiceDraftService
from app.database import Database, IdempotencyConflictError
from app.paypal import (
    PayPalConfigurationError,
    PayPalService,
    PayPalServiceError,
)
from app.schemas import (
    CheckoutConfirmation,
    InvoiceCreateRequest,
    InvoiceDraft,
    InvoiceDraftRequest,
    InvoiceOut,
)

load_dotenv(Path(__file__).resolve().parents[1] / ".env")
logger = logging.getLogger(__name__)
_bearer = HTTPBearer(auto_error=False)


@lru_cache(maxsize=1)
def get_database() -> Database:
    return Database()


@lru_cache(maxsize=1)
def get_paypal_service() -> PayPalService:
    return PayPalService()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    try:
        yield
    finally:
        if get_paypal_service.cache_info().currsize:
            await get_paypal_service().close()
            get_paypal_service.cache_clear()
        if get_database.cache_info().currsize:
            get_database().close()
            get_database.cache_clear()


app = FastAPI(title="AlvaPay API", version="0.1.0", lifespan=lifespan)
allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:8080").split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "alvapay-api"}


@app.post("/api/session", status_code=status.HTTP_201_CREATED)
def create_session(
    database: Annotated[Database, Depends(get_database)],
) -> dict[str, str]:
    return {"token": database.create_session()}


def require_owner(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(_bearer),
    ],
    database: Annotated[Database, Depends(get_database)],
) -> str:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Create a private AlvaPay session to continue.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    owner_id = database.owner_for_token(credentials.credentials)
    if owner_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="This AlvaPay session is no longer valid.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return owner_id


def get_invoice_draft_service() -> InvoiceDraftService:
    return InvoiceDraftService()


@app.post("/api/ai/draft", response_model=InvoiceDraft)
async def create_invoice_draft(
    request: InvoiceDraftRequest,
    service: Annotated[InvoiceDraftService, Depends(get_invoice_draft_service)],
    _owner_id: Annotated[str, Depends(require_owner)],
) -> InvoiceDraft:
    try:
        return await service.create_draft(request.text)
    except AIConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except AIProviderError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@app.post("/api/invoices", response_model=InvoiceOut, status_code=status.HTTP_201_CREATED)
def create_invoice(
    request: InvoiceCreateRequest,
    database: Annotated[Database, Depends(get_database)],
    owner_id: Annotated[str, Depends(require_owner)],
    idempotency_key: Annotated[
        str,
        Header(min_length=16, max_length=128, pattern=r"^[A-Za-z0-9._:-]+$"),
    ],
) -> InvoiceOut:
    try:
        invoice = database.create_invoice(
            request,
            owner_id=owner_id,
            idempotency_key=idempotency_key,
        )
    except IdempotencyConflictError as error:
        raise HTTPException(status_code=409, detail=str(error)) from error
    return InvoiceOut.model_validate(invoice)


@app.get("/api/invoices", response_model=list[InvoiceOut])
def list_invoices(
    database: Annotated[Database, Depends(get_database)],
    owner_id: Annotated[str, Depends(require_owner)],
) -> list[InvoiceOut]:
    return [
        InvoiceOut.model_validate(invoice) for invoice in database.list_invoices(owner_id=owner_id)
    ]


@app.get("/api/invoices/{invoice_id}", response_model=InvoiceOut)
def get_invoice(
    invoice_id: str,
    database: Annotated[Database, Depends(get_database)],
    owner_id: Annotated[str, Depends(require_owner)],
) -> InvoiceOut:
    invoice = database.get_invoice(invoice_id, owner_id=owner_id)
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    return InvoiceOut.model_validate(invoice)


@app.post("/api/invoices/{invoice_id}/checkout", response_model=InvoiceOut)
async def create_checkout(
    invoice_id: str,
    confirmation: CheckoutConfirmation,
    database: Annotated[Database, Depends(get_database)],
    paypal: Annotated[PayPalService, Depends(get_paypal_service)],
    owner_id: Annotated[str, Depends(require_owner)],
) -> InvoiceOut:
    reviewed_invoice = database.get_invoice(invoice_id, owner_id=owner_id)
    if reviewed_invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    if (
        confirmation.amount_cents != reviewed_invoice["amount_cents"]
        or confirmation.currency != reviewed_invoice["currency"]
    ):
        raise HTTPException(
            status_code=409,
            detail="The invoice changed after review. Review the exact amount before checkout.",
        )

    invoice = database.begin_checkout(invoice_id, owner_id=owner_id)
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    if invoice["status"] == "CHECKOUT_PENDING":
        saved = database.get_invoice(invoice_id, owner_id=owner_id)
        if saved is None:
            raise HTTPException(status_code=404, detail="Invoice not found.")
        return InvoiceOut.model_validate(saved)
    if invoice["status"] != "ORDER_CREATING":
        raise HTTPException(
            status_code=409,
            detail="This invoice is not available for checkout.",
        )

    try:
        order = await paypal.create_order(
            invoice_id=invoice_id,
            description=str(invoice["service_description"]),
            amount_cents=int(invoice["amount_cents"]),
            currency=str(invoice["currency"]),
            request_id=str(invoice["checkout_request_id"]),
        )
    except PayPalConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except PayPalServiceError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    saved = database.save_order(
        invoice_id,
        owner_id=owner_id,
        order_id=order.order_id,
        approval_url=order.approval_url,
    )
    return InvoiceOut.model_validate(saved)


@app.post("/api/invoices/{invoice_id}/capture", response_model=InvoiceOut)
async def capture_invoice(
    invoice_id: str,
    database: Annotated[Database, Depends(get_database)],
    paypal: Annotated[PayPalService, Depends(get_paypal_service)],
    owner_id: Annotated[str, Depends(require_owner)],
) -> InvoiceOut:
    invoice = database.begin_capture(invoice_id, owner_id=owner_id)
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    if invoice["status"] == "PAID":
        return InvoiceOut.model_validate(database.get_invoice(invoice_id, owner_id=owner_id))
    if invoice["status"] != "CAPTURE_IN_PROGRESS":
        raise HTTPException(
            status_code=409,
            detail="Approve the PayPal Sandbox checkout before confirming payment.",
        )

    try:
        order = await paypal.get_order(str(invoice["paypal_order_id"]))
        if not _order_matches_invoice(order, invoice):
            raise HTTPException(
                status_code=502,
                detail="PayPal order details did not match this invoice.",
            )
        if order.get("status") == "COMPLETED":
            capture_id = _verified_capture_id(order, invoice)
            if capture_id is None:
                raise HTTPException(
                    status_code=502,
                    detail="PayPal has not verified the complete invoice amount.",
                )
            return InvoiceOut.model_validate(
                database.mark_paid(
                    invoice_id,
                    owner_id=owner_id,
                    capture_id=capture_id,
                )
            )
        if order.get("status") != "APPROVED":
            database.release_capture(invoice_id, owner_id=owner_id)
            raise HTTPException(
                status_code=409,
                detail="PayPal has not approved this checkout yet.",
            )

        capture = await paypal.capture_order(
            str(invoice["paypal_order_id"]),
            request_id=str(invoice["capture_request_id"]),
        )
    except PayPalConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except PayPalServiceError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    capture_id = _verified_capture_id(capture, invoice)
    if capture_id is None:
        raise HTTPException(
            status_code=502,
            detail="PayPal has not verified the captured invoice amount. Refresh and try again.",
        )
    return InvoiceOut.model_validate(
        database.mark_paid(invoice_id, owner_id=owner_id, capture_id=capture_id)
    )


@app.post("/api/invoices/{invoice_id}/refresh", response_model=InvoiceOut)
async def refresh_invoice(
    invoice_id: str,
    database: Annotated[Database, Depends(get_database)],
    paypal: Annotated[PayPalService, Depends(get_paypal_service)],
    owner_id: Annotated[str, Depends(require_owner)],
) -> InvoiceOut:
    invoice = database.get_invoice(invoice_id, owner_id=owner_id)
    if invoice is None:
        raise HTTPException(status_code=404, detail="Invoice not found.")
    if invoice["status"] == "PAID" or not invoice["paypal_order_id"]:
        return InvoiceOut.model_validate(invoice)

    try:
        order = await paypal.get_order(str(invoice["paypal_order_id"]))
    except PayPalConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except PayPalServiceError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    if order.get("status") == "COMPLETED":
        record = database.begin_capture(invoice_id, owner_id=owner_id)
        if record is None or not _order_matches_invoice(order, record):
            raise HTTPException(
                status_code=502, detail="PayPal order details could not be verified."
            )
        capture_id = _verified_capture_id(order, record)
        if capture_id is None:
            raise HTTPException(
                status_code=502,
                detail="PayPal has not verified the complete invoice amount.",
            )
        return InvoiceOut.model_validate(
            database.mark_paid(invoice_id, owner_id=owner_id, capture_id=capture_id)
        )

    return InvoiceOut.model_validate(invoice)


def _order_matches_invoice(
    order: Mapping[str, Any],
    invoice: Mapping[str, object],
) -> bool:
    if order.get("id") != invoice.get("paypal_order_id"):
        return False
    purchase_units = order.get("purchase_units")
    if not isinstance(purchase_units, list):
        return False
    for unit in purchase_units:
        if not isinstance(unit, dict):
            continue
        if unit.get("custom_id") != invoice.get("id"):
            continue
        if unit.get("reference_id") != invoice.get("id"):
            continue
        amount = unit.get("amount")
        if not isinstance(amount, dict) or amount.get("currency_code") != invoice.get("currency"):
            continue
        try:
            actual = Decimal(str(amount["value"]))
            expected = Decimal(int(invoice["amount_cents"])) / Decimal(100)
        except (InvalidOperation, KeyError, TypeError, ValueError):
            continue
        if actual == expected:
            return True
    return False


def _verified_capture_id(
    order: Mapping[str, Any],
    invoice: Mapping[str, object],
) -> str | None:
    if order.get("id") != invoice.get("paypal_order_id") or order.get("status") != "COMPLETED":
        return None
    purchase_units = order.get("purchase_units")
    if not isinstance(purchase_units, list):
        return None
    for unit in purchase_units:
        if not isinstance(unit, dict) or unit.get("custom_id") != invoice.get("id"):
            continue
        if unit.get("reference_id") != invoice.get("id"):
            continue
        payments = unit.get("payments")
        captures = payments.get("captures") if isinstance(payments, dict) else None
        if not isinstance(captures, list):
            continue
        for capture in captures:
            if not isinstance(capture, dict) or capture.get("status") != "COMPLETED":
                continue
            amount = capture.get("amount")
            if not isinstance(amount, dict) or amount.get("currency_code") != invoice.get(
                "currency"
            ):
                continue
            try:
                actual = Decimal(str(amount["value"]))
                expected = Decimal(int(invoice["amount_cents"])) / Decimal(100)
            except (InvalidOperation, KeyError, TypeError, ValueError):
                continue
            capture_id = capture.get("id")
            if actual == expected and isinstance(capture_id, str) and capture_id:
                return capture_id
    return None
