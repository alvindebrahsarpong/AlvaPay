# AlvaPay — Hackathon Submission

## Short description

AlvaPay helps freelancers turn a plain-language project brief into an
editable invoice draft, then request payment through PayPal Sandbox after the
user reviews and confirms the exact amount.

## Problem

Freelancers and small businesses lose time converting client conversations
into invoices and following the payment workflow. AI can reduce the
administrative work, but a payment assistant must keep the person in control
and must not mistake a browser redirect for a completed payment.

## How it works

1. The user describes an invoice in natural language.
2. The FastAPI backend requests a schema-constrained draft from Anthropic
   Claude and validates it with Pydantic.
3. The user reviews and edits the details, then saves the invoice to
   owner-scoped SQLite storage.
4. The user explicitly confirms the exact amount and currency.
5. The backend creates a PayPal Sandbox Checkout Orders v2 order and returns
   only its verified Sandbox approval link to the Flutter client.
6. After the buyer approves, the user asks AlvaPay to verify/capture the
   order. The backend checks PayPal's order and capture status, amount, and
   currency before marking the invoice paid.

## Tools and technologies

- Flutter and Dart — responsive Web and Android client.
- Python, FastAPI, Pydantic, and HTTPX — validated API and provider requests.
- SQLite — persistent invoice and private-session records for the MVP.
- Anthropic Claude — structured natural-language invoice extraction.
- PayPal Checkout Orders v2 — Sandbox order creation, approval, and verified
  capture.

## PayPal integration

PayPal is used for actual Checkout Orders API calls against the Sandbox host.
PayPal credentials remain in backend environment variables. The client
requires explicit confirmation and sends the reviewed amount and currency;
the backend checks them against the stored invoice. The app accepts only
Sandbox approval links. Payment is marked paid only after a server-side
PayPal response verifies the completed order and capture. Provider behavior
has not yet been exercised with credentials in this development environment;
the tests use synthetic HTTP responses.

## AI integration

The implemented AI provider is Anthropic, using the configurable `AI_MODEL`
ID (default `claude-sonnet-5-5`) and schema-constrained output for extracting
customer name/email, service description, amount in integer cents, supported
currency, and due date. Pydantic validates the result before it reaches the
client. AI is limited to drafting; it cannot create, approve, or capture a
payment.

## Safety and privacy

- No provider secrets are included in Flutter or source control.
- Session bearer tokens are stored as hashes by the backend and in platform
  secure storage by the app.
- Invoice records are scoped to the session that created them.
- Checkout requires an explicit user action and matching amount/currency.
- Payment status is not trusted from the app or from a success redirect.
- Demo data should be synthetic; only PayPal Sandbox credentials and buyer
  accounts should be used.

## Current limitations

This is an MVP, not a production accounting system. The current repository
does not implement receipt-photo extraction, payment webhooks, reminders,
AI cash-flow summaries/chat, multi-provider AI support, PostgreSQL, or
production PayPal checkout. No live AI request or Sandbox payment has been
verified in the development environment. Follow the setup and deployment
notes in the [README](../README.md), and report these limitations honestly in
a demo.
