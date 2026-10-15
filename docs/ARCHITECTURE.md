# Architecture

AlvaPay is a Flutter client backed by a Python API. Integrations are built
incrementally; payment status is only persisted after server-side verification.

```mermaid
flowchart LR
    Person[User] --> Flutter[Flutter Web / Android]
    Flutter -->|HTTPS JSON API|     API[FastAPI + Pydantic]
    API --> SQLite[(SQLite)]
    API --> AI[Configured AI provider]
    API -->|PayPal Checkout Orders v2| Sandbox[PayPal Sandbox]
```

The Flutter client is untrusted and contains no provider credentials. The
backend owns AI parsing, validation, persistence, order creation, capture, and
payment verification. Creating checkout is gated by explicit user confirmation.
