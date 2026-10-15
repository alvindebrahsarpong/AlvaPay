import pytest
from pydantic import ValidationError

from app.schemas import CheckoutConfirmation, InvoiceDraft, InvoiceDraftRequest


def test_invoice_draft_preserves_integer_minor_units() -> None:
    draft = InvoiceDraft.model_validate(
        {
            "customer_name": "Ada Studio",
            "customer_email": "billing@example.test",
            "service_description": "Brand identity",
            "amount_cents": 8450,
            "currency": "USD",
            "due_date": "2026-10-20",
        }
    )

    assert draft.amount_cents == 8450
    assert draft.due_date == "2026-10-20"


@pytest.mark.parametrize(
    "field,value",
    [
        ("amount_cents", -1),
        ("amount_cents", "8450"),
        ("currency", "GHS"),
        ("customer_email", "not-an-email"),
        ("due_date", "20-10-2026"),
    ],
)
def test_invoice_draft_rejects_invalid_fields(field: str, value: object) -> None:
    draft = {
        "customer_name": None,
        "customer_email": None,
        "service_description": "Brand identity",
        "amount_cents": 8450,
        "currency": "USD",
        "due_date": None,
    }
    draft[field] = value

    with pytest.raises(ValidationError):
        InvoiceDraft.model_validate(draft)


def test_invoice_draft_request_rejects_empty_or_oversized_text() -> None:
    with pytest.raises(ValidationError):
        InvoiceDraftRequest(text="short")

    with pytest.raises(ValidationError):
        InvoiceDraftRequest(text="x" * 4001)


def test_checkout_confirmation_requires_the_reviewed_amount() -> None:
    confirmation = CheckoutConfirmation.model_validate(
        {"confirmed": True, "amount_cents": 8450, "currency": "USD"}
    )
    assert confirmation.amount_cents == 8450


@pytest.mark.parametrize(
    "payload",
    [
        {"confirmed": False, "amount_cents": 8450, "currency": "USD"},
        {"confirmed": True, "amount_cents": 8450, "currency": "GHS"},
        {"confirmed": True, "amount_cents": "8450", "currency": "USD"},
    ],
)
def test_checkout_confirmation_rejects_invalid_confirmation(payload: dict[str, object]) -> None:
    with pytest.raises(ValidationError):
        CheckoutConfirmation.model_validate(payload)
