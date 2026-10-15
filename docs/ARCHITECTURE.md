# Architecture

Initial milestone scaffold; integrations and persistence will be added in later
milestones.

```mermaid
flowchart LR
    Person[User] --> Flutter[Flutter Web / Android]
    Flutter -->|HTTPS JSON API| API[Express + TypeScript API]
    API --> SQLite[(SQLite)]
    API --> AI[Configured AI provider]
    API -->|PayPal Invoicing v2| Sandbox[PayPal Sandbox]
    Sandbox -->|Verified invoice webhooks| API
```

The Flutter client is untrusted and contains no provider credentials. The
backend owns parsing, validation, persistence, invoice creation, status
tracking, reminders, and chat tools. Invoice creation is gated by an explicit
user confirmation.
