# AlvaPay

**Invoice clearly. Settle confidently.**

AlvaPay helps freelancers turn a plain-language brief into a reviewable invoice
draft, then creates and captures PayPal Sandbox orders only after the user
explicitly confirms the details.

## Project status

Stages 1–6 are implemented: a responsive Flutter app connected to the FastAPI
draft, persistence, and PayPal Sandbox checkout workflow. Users can review an
AI-assisted draft, save it to SQLite, explicitly confirm its exact amount, open
PayPal Sandbox, then ask the backend to capture and verify the order. Tests use
synthetic provider responses; no live AI request or PayPal Sandbox payment has
been made. Cash-flow chat, production deployment, and submission materials
remain future work.

## Repository layout

```text
alvapay/
|-- app/             Flutter app (Web and Android)
|-- backend/         Python, FastAPI API and tests
|-- docs/            Architecture and demo materials
|-- .env.example     Backend configuration template (no credentials)
|-- LICENSE          MIT
`-- README.md
```

## Prerequisites

- Flutter stable with Dart SDK constraints satisfied by `app/pubspec.yaml`.
- Python 3.12 or later and `pip`.

## Run locally

1. Copy `.env.example` to `backend/.env` and fill in credentials when ready.
   The Flutter app must never contain backend or provider secrets.
2. Install and run the API:

   ```powershell
   Set-Location backend
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   py -m pip install -e ".[dev]"
   Copy-Item ..\.env.example .env
   py -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

   The API listens on `http://localhost:8000`; check
   `http://localhost:8000/api/health`.
3. In another terminal, run the Flutter app:

   ```powershell
   Set-Location app
   flutter pub get
   flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
   ```

   The app stores its private anonymous session token using platform secure
   storage. For a local Android emulator, the default API address is
   `http://10.0.2.2:8000`; run the backend on the host and launch:

   ```powershell
   flutter run -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000
   ```

   Debug builds permit local cleartext HTTP for emulator development only.
   Use an HTTPS backend URL for hosted Web builds and production Android
   releases. `API_BASE_URL` is a public endpoint, not a secret.

## Build and test

```powershell
Set-Location backend
py -m pytest
ruff check .

Set-Location ..\app
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

## Product and architecture

AlvaPay uses an AI provider to prepare a structured invoice draft from natural
language. People can review and edit the draft before explicit confirmation
creates a PayPal Sandbox checkout order. Payment status is only updated after
server-side verification with PayPal.

The backend's `POST /api/ai/draft` endpoint uses Anthropic's Messages API with
JSON Schema structured output and validates the returned draft again with
Pydantic. The default model is `claude-sonnet-5-5`; set `AI_MODEL` to an
available model and `AI_API_KEY` in `backend/.env`. If the key is missing, the
endpoint returns a clear configuration error; it does not fabricate a draft.
The extraction request sends the invoice description to the configured AI
provider.

The current backend workflow is:

1. `POST /api/session` creates a private anonymous session. Send its bearer
   token to the authenticated routes; only a hash of the token is stored.
2. `POST /api/ai/draft` analyzes an invoice description when an AI key is
   configured.
3. After review, `POST /api/invoices` saves the exact details. Include an
   `Idempotency-Key` header so a retried save cannot create a duplicate.
4. Only after the user confirms the displayed amount, call
   `POST /api/invoices/{id}/checkout` with
   `{"confirmed":true,"amount_cents":8450,"currency":"USD"}` (using the
   reviewed invoice values); the API rejects missing or mismatched
   confirmations. Open the returned `approval_url` for PayPal Sandbox approval.
5. After approval, call `POST /api/invoices/{id}/capture`. The backend fetches
   and validates the PayPal order and capture amount/currency before it marks
   the invoice paid. Client-provided success statuses are ignored.
6. Use `GET /api/invoices` or `GET /api/invoices/{id}` to read persisted status.

PayPal order creation, capture, and invoice saves have stable idempotency
protection. The backend currently uses polling during capture/refresh; PayPal
webhooks, and AI cash-flow summaries/chat remain future work. The Flutter app
is wired to the draft, invoice, checkout, capture, and refresh routes, and keeps
the session token out of source control. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the system diagram.

Without provider credentials, the backend deliberately returns a clear
configuration error for AI drafting or PayPal checkout; the app does not
substitute sample AI or payment results. Add sandbox credentials only to
`backend/.env` using [.env.example](.env.example) as a guide. Do not put them in
Flutter build defines or paste them into source files.

## Security

Keep all PayPal and AI credentials in backend environment variables. Never
commit `.env` files, database files, access tokens, or real customer data.
PayPal integrations are sandbox-only for this project.

## License

AlvaPay is released under the MIT License; see [LICENSE](LICENSE).
