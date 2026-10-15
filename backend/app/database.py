import hashlib
import hmac
import json
import os
import secrets
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from threading import RLock
from uuid import uuid4

from app.schemas import InvoiceCreateRequest


class IdempotencyConflictError(Exception):
    pass


class AccountAlreadyExistsError(Exception):
    pass


_PASSWORD_ITERATIONS = 310_000


def _hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        _PASSWORD_ITERATIONS,
    )
    return f"pbkdf2_sha256${_PASSWORD_ITERATIONS}${salt.hex()}${digest.hex()}"


def _verify_password(password: str, stored_hash: str) -> bool:
    try:
        algorithm, iterations, salt_hex, expected_hex = stored_hash.split("$", 3)
        if algorithm != "pbkdf2_sha256" or int(iterations) != _PASSWORD_ITERATIONS:
            return False
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(expected_hex)
    except (TypeError, ValueError):
        return False
    actual = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt,
        _PASSWORD_ITERATIONS,
    )
    return hmac.compare_digest(actual, expected)


_DUMMY_PASSWORD_HASH = _hash_password("alvapay-nonexistent-account-password")


class Database:
    def __init__(self, path: str | Path | None = None) -> None:
        configured_path = str(path or os.getenv("DATABASE_PATH", "./data/alvapay.sqlite3"))
        if configured_path != ":memory:":
            Path(configured_path).parent.mkdir(parents=True, exist_ok=True)
        self._connection = sqlite3.connect(
            configured_path,
            timeout=10,
            isolation_level=None,
            check_same_thread=False,
        )
        self._connection.row_factory = sqlite3.Row
        self._connection.execute("PRAGMA foreign_keys = ON")
        self._connection.execute("PRAGMA journal_mode = WAL")
        self._lock = RLock()
        self._initialize()

    def close(self) -> None:
        with self._lock:
            self._connection.close()

    def create_account(self, email: str, password: str) -> str:
        owner_id = str(uuid4())
        password_hash = _hash_password(password)
        with self._transaction() as connection:
            existing = connection.execute(
                "SELECT 1 FROM accounts WHERE email = ?",
                (email,),
            ).fetchone()
            if existing is not None:
                raise AccountAlreadyExistsError("An account with this email already exists.")
            connection.execute(
                """
                INSERT INTO accounts (owner_id, email, password_hash, created_at)
                VALUES (?, ?, ?, ?)
                """,
                (owner_id, email, password_hash, _now()),
            )
        return owner_id

    def authenticate_account(self, email: str, password: str) -> str | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT owner_id, password_hash FROM accounts WHERE email = ?",
                (email,),
            ).fetchone()
        password_hash = str(row["password_hash"]) if row is not None else _DUMMY_PASSWORD_HASH
        if not _verify_password(password, password_hash) or row is None:
            return None
        return str(row["owner_id"])

    def account_email(self, owner_id: str) -> str | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT email FROM accounts WHERE owner_id = ?",
                (owner_id,),
            ).fetchone()
        return str(row["email"]) if row is not None else None

    def create_session(self, owner_id: str | None = None) -> str:
        owner_id = owner_id or str(uuid4())
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._transaction() as connection:
            connection.execute("DELETE FROM sessions WHERE owner_id = ?", (owner_id,))
            connection.execute(
                "INSERT INTO sessions (owner_id, token_hash, created_at) VALUES (?, ?, ?)",
                (owner_id, token_hash, _now()),
            )
        return token

    def revoke_session(self, token: str) -> bool:
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._transaction() as connection:
            cursor = connection.execute(
                "DELETE FROM sessions WHERE token_hash = ?",
                (token_hash,),
            )
        return cursor.rowcount == 1

    def owner_for_token(self, token: str) -> str | None:
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        with self._lock:
            row = self._connection.execute(
                "SELECT owner_id FROM sessions WHERE token_hash = ?",
                (token_hash,),
            ).fetchone()
        return str(row["owner_id"]) if row is not None else None

    def create_invoice(
        self,
        invoice: InvoiceCreateRequest,
        *,
        owner_id: str,
        idempotency_key: str,
    ) -> dict[str, object]:
        now = _now()
        request_hash = hashlib.sha256(
            json.dumps(invoice.model_dump(mode="json"), sort_keys=True).encode("utf-8")
        ).hexdigest()
        values: dict[str, object] = {
            "id": str(uuid4()),
            "owner_id": owner_id,
            "customer_name": invoice.customer_name,
            "customer_email": invoice.customer_email,
            "service_description": invoice.service_description,
            "amount_cents": invoice.amount_cents,
            "currency": invoice.currency,
            "due_date": invoice.due_date,
            "status": "DRAFT",
            "paypal_order_id": None,
            "approval_url": None,
            "paypal_capture_id": None,
            "checkout_request_id": str(uuid4()),
            "capture_request_id": str(uuid4()),
            "created_at": now,
            "updated_at": now,
        }
        with self._transaction() as connection:
            previous = connection.execute(
                """
                SELECT request_hash, invoice_id
                FROM invoice_idempotency
                WHERE owner_id = ? AND idempotency_key = ?
                """,
                (owner_id, idempotency_key),
            ).fetchone()
            if previous is not None:
                if previous["request_hash"] != request_hash:
                    raise IdempotencyConflictError(
                        "This idempotency key was already used with different invoice details."
                    )
                row = connection.execute(
                    "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                    (previous["invoice_id"], owner_id),
                ).fetchone()
                if row is None:
                    raise RuntimeError("The saved idempotent invoice record is missing.")
                return _public_invoice(row)

            connection.execute(
                """
                INSERT INTO invoices (
                    id, owner_id, customer_name, customer_email, service_description,
                    amount_cents, currency, due_date, status, paypal_order_id,
                    approval_url, paypal_capture_id, checkout_request_id,
                    capture_request_id, created_at, updated_at
                ) VALUES (
                    :id, :owner_id, :customer_name, :customer_email, :service_description,
                    :amount_cents, :currency, :due_date, :status, :paypal_order_id,
                    :approval_url, :paypal_capture_id, :checkout_request_id,
                    :capture_request_id, :created_at, :updated_at
                )
                """,
                values,
            )
            connection.execute(
                """
                INSERT INTO invoice_idempotency (
                    owner_id, idempotency_key, request_hash, invoice_id
                ) VALUES (?, ?, ?, ?)
                """,
                (owner_id, idempotency_key, request_hash, values["id"]),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (values["id"], owner_id),
            ).fetchone()
        if row is None:
            raise RuntimeError("Invoice insert did not return a saved record.")
        return _public_invoice(row)

    def list_invoices(self, *, owner_id: str) -> list[dict[str, object]]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT * FROM invoices WHERE owner_id = ? ORDER BY created_at DESC",
                (owner_id,),
            ).fetchall()
        return [_public_invoice(row) for row in rows]

    def verified_payment_totals(self, *, owner_id: str) -> list[dict[str, object]]:
        with self._lock:
            rows = self._connection.execute(
                """
                SELECT currency, COUNT(*) AS paid_invoice_count,
                    SUM(amount_cents) AS received_cents
                FROM invoices
                WHERE owner_id = ? AND status = 'PAID' AND paypal_capture_id IS NOT NULL
                GROUP BY currency
                ORDER BY currency
                """,
                (owner_id,),
            ).fetchall()
        return [
            {
                "currency": str(row["currency"]),
                "paid_invoice_count": int(row["paid_invoice_count"]),
                "received_cents": int(row["received_cents"]),
            }
            for row in rows
        ]

    def get_invoice(self, invoice_id: str, *, owner_id: str) -> dict[str, object] | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, owner_id),
            ).fetchone()
        return _public_invoice(row) if row is not None else None

    def begin_checkout(
        self,
        invoice_id: str,
        *,
        owner_id: str,
    ) -> dict[str, object] | None:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'ORDER_CREATING', updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'DRAFT'
                """,
                (_now(), invoice_id, owner_id),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, owner_id),
            ).fetchone()
        return dict(row) if row is not None else None

    def release_capture(self, invoice_id: str, *, owner_id: str) -> None:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'CHECKOUT_PENDING', updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'CAPTURE_IN_PROGRESS'
                """,
                (_now(), invoice_id, owner_id),
            )

    def save_order(
        self,
        invoice_id: str,
        *,
        owner_id: str,
        order_id: str,
        approval_url: str,
    ) -> dict[str, object]:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'CHECKOUT_PENDING', paypal_order_id = ?, approval_url = ?,
                    updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'ORDER_CREATING'
                """,
                (order_id, approval_url, _now(), invoice_id, owner_id),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, owner_id),
            ).fetchone()
        if row is None:
            raise RuntimeError("Invoice was not found while saving the PayPal order.")
        if row["paypal_order_id"] != order_id:
            raise RuntimeError("Invoice PayPal order state changed unexpectedly.")
        return _public_invoice(row)

    def begin_capture(
        self,
        invoice_id: str,
        *,
        owner_id: str,
    ) -> dict[str, object] | None:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'CAPTURE_IN_PROGRESS', updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'CHECKOUT_PENDING'
                """,
                (_now(), invoice_id, owner_id),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, owner_id),
            ).fetchone()
        return dict(row) if row is not None else None

    def mark_paid(
        self,
        invoice_id: str,
        *,
        owner_id: str,
        capture_id: str,
    ) -> dict[str, object]:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'PAID', paypal_capture_id = ?, updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'CAPTURE_IN_PROGRESS'
                """,
                (capture_id, _now(), invoice_id, owner_id),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, owner_id),
            ).fetchone()
        if row is None:
            raise RuntimeError("Invoice was not found while saving the verified capture.")
        if row["status"] != "PAID" or row["paypal_capture_id"] != capture_id:
            raise RuntimeError("Invoice payment state changed unexpectedly.")
        return _public_invoice(row)

    @contextmanager
    def _transaction(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            self._connection.execute("BEGIN IMMEDIATE")
            try:
                yield self._connection
            except Exception:
                self._connection.rollback()
                raise
            else:
                self._connection.commit()

    def _initialize(self) -> None:
        with self._lock:
            self._connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS accounts (
                    owner_id TEXT PRIMARY KEY,
                    email TEXT NOT NULL UNIQUE,
                    password_hash TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS sessions (
                    owner_id TEXT PRIMARY KEY,
                    token_hash TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS invoices (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    customer_name TEXT NOT NULL,
                    customer_email TEXT NOT NULL,
                    service_description TEXT NOT NULL,
                    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
                    currency TEXT NOT NULL CHECK (length(currency) = 3),
                    due_date TEXT,
                    status TEXT NOT NULL CHECK (
                        status IN (
                            'DRAFT', 'ORDER_CREATING', 'CHECKOUT_PENDING',
                            'CAPTURE_IN_PROGRESS', 'PAID'
                        )
                    ),
                    paypal_order_id TEXT UNIQUE,
                    approval_url TEXT,
                    paypal_capture_id TEXT UNIQUE,
                    checkout_request_id TEXT NOT NULL UNIQUE,
                    capture_request_id TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS invoices_owner_created
                    ON invoices (owner_id, created_at DESC);
                CREATE TABLE IF NOT EXISTS invoice_idempotency (
                    owner_id TEXT NOT NULL,
                    idempotency_key TEXT NOT NULL,
                    request_hash TEXT NOT NULL,
                    invoice_id TEXT NOT NULL UNIQUE,
                    PRIMARY KEY (owner_id, idempotency_key),
                    FOREIGN KEY (invoice_id) REFERENCES invoices (id)
                );
                """
            )


def _public_invoice(row: sqlite3.Row) -> dict[str, object]:
    return {
        "id": row["id"],
        "customer_name": row["customer_name"],
        "customer_email": row["customer_email"],
        "service_description": row["service_description"],
        "amount_cents": row["amount_cents"],
        "currency": row["currency"],
        "due_date": row["due_date"],
        "status": row["status"],
        "paypal_order_id": row["paypal_order_id"],
        "approval_url": row["approval_url"],
        "paypal_capture_id": row["paypal_capture_id"],
        "created_at": row["created_at"],
    }


def _now() -> str:
    return datetime.now(UTC).isoformat()
