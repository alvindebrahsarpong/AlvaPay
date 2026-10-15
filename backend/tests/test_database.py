import pytest

from app.database import Database, IdempotencyConflictError
from app.schemas import InvoiceCreateRequest


def _invoice_request() -> InvoiceCreateRequest:
    return InvoiceCreateRequest(
        customer_name="Ada Studio",
        customer_email="billing@example.test",
        service_description="Brand identity",
        amount_cents=8450,
        currency="USD",
        due_date="2026-10-20",
    )


def test_sessions_are_random_and_stored_as_hashes() -> None:
    database = Database(":memory:")
    try:
        first = database.create_session()
        second = database.create_session()

        assert first != second
        assert database.owner_for_token(first) is not None
        assert database.owner_for_token(second) is not None
        assert database.owner_for_token("not-a-session") is None
        assert first not in {
            row["token_hash"]
            for row in database._connection.execute("SELECT token_hash FROM sessions").fetchall()
        }
    finally:
        database.close()


def test_account_passwords_are_hashed_and_sessions_can_be_revoked() -> None:
    database = Database(":memory:")
    try:
        owner_id = database.create_account("user@example.test", "correct-horse-battery")
        password_hash = database._connection.execute(
            "SELECT password_hash FROM accounts WHERE owner_id = ?",
            (owner_id,),
        ).fetchone()["password_hash"]
        token = database.create_session(owner_id)

        assert password_hash != "correct-horse-battery"
        assert database.authenticate_account("user@example.test", "wrong-password") is None
        assert database.authenticate_account(
            "user@example.test",
            "correct-horse-battery",
        ) == owner_id
        assert database.owner_for_token(token) == owner_id
        assert database.revoke_session(token) is True
        assert database.owner_for_token(token) is None
        assert database.revoke_session(token) is False
    finally:
        database.close()


def test_invoice_and_session_survive_database_reopen(tmp_path) -> None:
    path = tmp_path / "alvapay.sqlite3"
    first = Database(path)
    token = first.create_session()
    owner_id = first.owner_for_token(token)
    assert owner_id is not None
    invoice = first.create_invoice(
        _invoice_request(),
        owner_id=owner_id,
        idempotency_key="persisted-invoice-0001",
    )
    invoice_id = str(invoice["id"])
    first.close()

    reopened = Database(path)
    try:
        assert reopened.owner_for_token(token) == owner_id
        assert reopened.get_invoice(invoice_id, owner_id=owner_id) == invoice
    finally:
        reopened.close()


def test_invoice_reads_are_scoped_to_the_session_owner() -> None:
    database = Database(":memory:")
    try:
        first_token = database.create_session()
        second_token = database.create_session()
        first_owner = database.owner_for_token(first_token)
        second_owner = database.owner_for_token(second_token)
        assert first_owner is not None and second_owner is not None

        invoice = database.create_invoice(
            _invoice_request(),
            owner_id=first_owner,
            idempotency_key="owner-scoped-invoice-0001",
        )

        assert database.get_invoice(invoice["id"], owner_id=first_owner) == invoice
        assert database.get_invoice(invoice["id"], owner_id=second_owner) is None
        assert database.list_invoices(owner_id=second_owner) == []
    finally:
        database.close()


def test_checkout_state_is_idempotent_and_paid_requires_capture_transition() -> None:
    database = Database(":memory:")
    try:
        token = database.create_session()
        owner_id = database.owner_for_token(token)
        assert owner_id is not None
        invoice = database.create_invoice(
            _invoice_request(),
            owner_id=owner_id,
            idempotency_key="checkout-invoice-0001",
        )
        invoice_id = str(invoice["id"])

        checkout = database.begin_checkout(invoice_id, owner_id=owner_id)
        assert checkout is not None
        checkout_request_id = checkout["checkout_request_id"]
        retry = database.begin_checkout(invoice_id, owner_id=owner_id)
        assert retry is not None
        assert retry["checkout_request_id"] == checkout_request_id

        pending = database.save_order(
            invoice_id,
            owner_id=owner_id,
            order_id="ORDER-1",
            approval_url="https://www.sandbox.paypal.com/checkoutnow?token=ORDER-1",
        )
        assert pending["status"] == "CHECKOUT_PENDING"

        capture = database.begin_capture(invoice_id, owner_id=owner_id)
        assert capture is not None
        assert capture["status"] == "CAPTURE_IN_PROGRESS"
        paid = database.mark_paid(invoice_id, owner_id=owner_id, capture_id="CAPTURE-1")

        assert paid["status"] == "PAID"
        assert paid["paypal_capture_id"] == "CAPTURE-1"
    finally:
        database.close()


def test_invoice_creation_is_idempotent_and_rejects_key_reuse() -> None:
    database = Database(":memory:")
    try:
        owner_id = database.owner_for_token(database.create_session())
        assert owner_id is not None
        request = _invoice_request()
        first = database.create_invoice(
            request,
            owner_id=owner_id,
            idempotency_key="invoice-create-request-0001",
        )
        retry = database.create_invoice(
            request,
            owner_id=owner_id,
            idempotency_key="invoice-create-request-0001",
        )

        assert retry["id"] == first["id"]
        assert len(database.list_invoices(owner_id=owner_id)) == 1
        with pytest.raises(IdempotencyConflictError):
            database.create_invoice(
                request.model_copy(update={"amount_cents": 9000}),
                owner_id=owner_id,
                idempotency_key="invoice-create-request-0001",
            )
    finally:
        database.close()


def test_verified_payment_totals_exclude_unpaid_invoices_and_other_owners() -> None:
    database = Database(":memory:")
    try:
        owner_id = database.owner_for_token(database.create_session())
        other_owner_id = database.owner_for_token(database.create_session())
        assert owner_id is not None and other_owner_id is not None

        def save_invoice(
            invoice_owner: str,
            *,
            key: str,
            amount_cents: int,
            currency: str,
        ) -> dict[str, object]:
            request = _invoice_request().model_copy(
                update={"amount_cents": amount_cents, "currency": currency}
            )
            return database.create_invoice(
                request,
                owner_id=invoice_owner,
                idempotency_key=key,
            )

        def mark_paid(invoice: dict[str, object], invoice_owner: str) -> None:
            invoice_id = str(invoice["id"])
            database.begin_checkout(invoice_id, owner_id=invoice_owner)
            database.save_order(
                invoice_id,
                owner_id=invoice_owner,
                order_id=f"ORDER-{invoice_id}",
                approval_url=(
                    "https://www.sandbox.paypal.com/checkoutnow?token="
                    f"ORDER-{invoice_id}"
                ),
            )
            database.begin_capture(invoice_id, owner_id=invoice_owner)
            database.mark_paid(
                invoice_id,
                owner_id=invoice_owner,
                capture_id=f"CAPTURE-{invoice_id}",
            )

        paid_usd = save_invoice(
            owner_id,
            key="verified-usd-payment-0001",
            amount_cents=8450,
            currency="USD",
        )
        paid_eur = save_invoice(
            owner_id,
            key="verified-eur-payment-0001",
            amount_cents=2500,
            currency="EUR",
        )
        unpaid = save_invoice(
            owner_id,
            key="unpaid-invoice-0001",
            amount_cents=17000,
            currency="USD",
        )
        other_owner_paid = save_invoice(
            other_owner_id,
            key="other-owner-payment-0001",
            amount_cents=99999,
            currency="USD",
        )
        mark_paid(paid_usd, owner_id)
        mark_paid(paid_eur, owner_id)
        mark_paid(other_owner_paid, other_owner_id)

        assert database.verified_payment_totals(owner_id=owner_id) == [
            {"currency": "EUR", "paid_invoice_count": 1, "received_cents": 2500},
            {"currency": "USD", "paid_invoice_count": 1, "received_cents": 8450},
        ]
        assert database.get_invoice(str(unpaid["id"]), owner_id=owner_id)["status"] == "DRAFT"
    finally:
        database.close()
