import re
from datetime import date
from typing import ClassVar, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

SUPPORTED_CURRENCIES: tuple[str, ...] = ("USD", "EUR", "GBP", "CAD")


class InvoiceDraftRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    text: str = Field(min_length=8, max_length=4000)


class InvoiceDraft(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    supported_currencies: ClassVar[tuple[str, ...]] = SUPPORTED_CURRENCIES

    customer_name: str | None = Field(default=None, max_length=120)
    customer_email: str | None = Field(default=None, max_length=254)
    service_description: str = Field(min_length=2, max_length=500)
    amount_cents: int | None = Field(default=None, strict=True, gt=0, le=100_000_000)
    currency: str | None = None
    due_date: str | None = None

    @field_validator("customer_name", "customer_email", mode="before")
    @classmethod
    def empty_optional_text_is_missing(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @field_validator("customer_email")
    @classmethod
    def validate_customer_email(cls, value: str | None) -> str | None:
        if value is not None and not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("Enter a valid customer email address.")
        return value

    @field_validator("currency")
    @classmethod
    def validate_currency(cls, value: str | None) -> str | None:
        if value is not None and value not in SUPPORTED_CURRENCIES:
            supported = ", ".join(SUPPORTED_CURRENCIES)
            raise ValueError(f"Currency must be one of: {supported}.")
        return value

    @field_validator("due_date")
    @classmethod
    def validate_due_date(cls, value: str | None) -> str | None:
        if value is not None:
            parsed = date.fromisoformat(value)
            if parsed.isoformat() != value:
                raise ValueError("Due date must use YYYY-MM-DD format.")
        return value


class InvoiceCreateRequest(InvoiceDraft):
    customer_name: str = Field(min_length=1, max_length=120)
    customer_email: str = Field(min_length=3, max_length=254)
    amount_cents: int = Field(strict=True, gt=0, le=100_000_000)
    currency: str


class CheckoutConfirmation(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    confirmed: Literal[True]
    amount_cents: int = Field(strict=True, gt=0, le=100_000_000)
    currency: str = Field(pattern=r"^(USD|EUR|GBP|CAD)$")


class AccountCredentials(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=12, max_length=128)

    @field_validator("email", mode="before")
    @classmethod
    def normalize_account_email(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip().lower()
        return value

    @field_validator("email")
    @classmethod
    def validate_account_email(cls, value: str) -> str:
        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", value):
            raise ValueError("Enter a valid email address.")
        return value


class AuthSessionOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    token: str
    email: str


class InvoiceOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    customer_name: str
    customer_email: str
    service_description: str
    amount_cents: int
    currency: str
    due_date: str | None
    status: str
    paypal_order_id: str | None
    approval_url: str | None
    paypal_capture_id: str | None
    created_at: str


class CashFlowCurrencyTotal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    currency: str = Field(pattern=r"^(USD|EUR|GBP|CAD)$")
    paid_invoice_count: int = Field(strict=True, gt=0)
    received_cents: int = Field(strict=True, gt=0)


class CashFlowSummaryText(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    summary: str = Field(min_length=10, max_length=400)


class CashFlowSummaryOut(BaseModel):
    model_config = ConfigDict(extra="forbid")

    verified_invoice_count: int = Field(strict=True, ge=0)
    totals_by_currency: list[CashFlowCurrencyTotal]
    summary: str = Field(min_length=1, max_length=400)
