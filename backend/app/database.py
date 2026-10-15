import os
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from threading import RLock
from uuid import uuid4

from app.schemas import InvoiceCreateRequest

_OWNER_ID = "local-owner"


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

    def create_invoice(self, invoice: InvoiceCreateRequest) -> dict[str, object]:
        now = _now()
        values: dict[str, object] = {
            "id": str(uuid4()),
            "owner_id": _OWNER_ID,
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
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (values["id"], _OWNER_ID),
            ).fetchone()
        if row is None:
            raise RuntimeError("Invoice insert did not return a saved record.")
        return _public_invoice(row)

    def list_invoices(self) -> list[dict[str, object]]:
        with self._lock:
            rows = self._connection.execute(
                "SELECT * FROM invoices WHERE owner_id = ? ORDER BY created_at DESC",
                (_OWNER_ID,),
            ).fetchall()
        return [_public_invoice(row) for row in rows]

    def get_invoice(self, invoice_id: str) -> dict[str, object] | None:
        with self._lock:
            row = self._connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, _OWNER_ID),
            ).fetchone()
        return _public_invoice(row) if row is not None else None

    def begin_checkout(self, invoice_id: str) -> dict[str, object] | None:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'ORDER_CREATING', updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'DRAFT'
                """,
                (_now(), invoice_id, _OWNER_ID),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, _OWNER_ID),
            ).fetchone()
        return _public_invoice(row) if row is not None else None

    def save_order(
        self,
        invoice_id: str,
        *,
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
                (order_id, approval_url, _now(), invoice_id, _OWNER_ID),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, _OWNER_ID),
            ).fetchone()
        if row is None:
            raise RuntimeError("Invoice was not found while saving the PayPal order.")
        if row["paypal_order_id"] != order_id:
            raise RuntimeError("Invoice PayPal order state changed unexpectedly.")
        return _public_invoice(row)

    def begin_capture(self, invoice_id: str) -> dict[str, object] | None:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'CAPTURE_IN_PROGRESS', updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'CHECKOUT_PENDING'
                """,
                (_now(), invoice_id, _OWNER_ID),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, _OWNER_ID),
            ).fetchone()
        return _public_invoice(row) if row is not None else None

    def mark_paid(self, invoice_id: str, *, capture_id: str) -> dict[str, object]:
        with self._transaction() as connection:
            connection.execute(
                """
                UPDATE invoices
                SET status = 'PAID', paypal_capture_id = ?, updated_at = ?
                WHERE id = ? AND owner_id = ? AND status = 'CAPTURE_IN_PROGRESS'
                """,
                (capture_id, _now(), invoice_id, _OWNER_ID),
            )
            row = connection.execute(
                "SELECT * FROM invoices WHERE id = ? AND owner_id = ?",
                (invoice_id, _OWNER_ID),
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
