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
been made. The app is not yet deployed, and conversational cash-flow chat,
payment webhooks, and receipt-photo extraction are not implemented.
Email/password registration, login, and revocable logout are implemented for
private MVP workspaces.

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

1. Copy `.env.example` to `backend/.env` once, then add credentials to that
   local file when ready. Do not repeat the copy after adding credentials. The
   Flutter app must never contain backend or provider secrets.
2. Install and run the API:

   ```powershell
   Copy-Item .env.example backend/.env
   Set-Location backend
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   py -m pip install -e ".[dev]"
   py -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
   ```

   The API listens on `http://localhost:8000`; check
   `http://localhost:8000/api/health`. Interactive API documentation is at
   `http://localhost:8000/docs`.
3. In another terminal, run the Flutter app:

   ```powershell
   Set-Location app
   flutter pub get
   flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
   ```

   The app stores its private session token using platform secure storage. To
   see the same invoices in a browser and on Android, sign in with the same
   account on both. Creating an account or signing in moves invoices from the
   current anonymous browser/app session into that account. Accounts may be
   signed in on multiple devices, and signing out revokes only that device's
   session.

   For a physical Android device connected over USB, forward the backend port
   and run the app; its default API address is the forwarded loopback URL,
   `http://127.0.0.1:8000`:

   ```powershell
   adb reverse tcp:8000 tcp:8000
   flutter run -d <phone-id>
   ```

   Keep `adb reverse` active while using the locally hosted backend. Debug
   builds permit local cleartext HTTP for development only. Use an HTTPS
   backend URL for hosted Web builds and production Android releases. Android
   emulators use `http://10.0.2.2:8000`; override the default with
   `--dart-define=API_BASE_URL=http://10.0.2.2:8000` when running on an emulator.
   `API_BASE_URL` is a public endpoint, not a secret.

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
available Anthropic model and `AI_API_KEY` (or `ANTHROPIC_API_KEY`) in
`backend/.env`. The model identifier is listed in the
[official Anthropic model overview](https://platform.claude.com/docs/en/models/overview).
Anthropic is the only implemented provider; `AI_PROVIDER` is validated rather
than silently falling back to another service. If the key is missing, the
endpoint returns a clear configuration error; it does not fabricate a draft.
The extraction request sends the invoice description to Anthropic. Receipt
images are not currently accepted.

The current backend workflow is:

1. `POST /api/session` creates a private anonymous session. For a named
   workspace, use `POST /api/auth/register` or `POST /api/auth/login` with an
   email and password (minimum 12 characters). Passwords are stored as
   PBKDF2-SHA256 hashes, session tokens are stored as hashes, and
   the current anonymous workspace's invoices are claimed by the account.
   `POST /api/auth/logout` revokes only the current bearer token. An account
   can have multiple active sessions, so signing in on one device does not
   sign out another. Email verification and password recovery are not
   included in this MVP.
2. Send the returned bearer token to authenticated routes.
   `POST /api/ai/draft` analyzes an invoice description when an AI key is
   configured.
3. `POST /api/ai/cash-flow-summary` summarizes all-time totals from this
   session's invoices whose status is `PAID` and that have a verified PayPal
   capture ID. Only currency-grouped counts and totals are sent to AI; customer
   details, drafts, and unpaid invoices are excluded.
4. After review, `POST /api/invoices` saves the exact details. Include an
   `Idempotency-Key` header so a retried save cannot create a duplicate.
5. Only after the user confirms the displayed amount, call
   `POST /api/invoices/{id}/checkout` with
   `{"confirmed":true,"amount_cents":8450,"currency":"USD"}` (using the
   reviewed invoice values); the API rejects missing or mismatched
   confirmations. Open the returned `approval_url` for PayPal Sandbox approval.
6. After approval, call `POST /api/invoices/{id}/capture`. The backend fetches
   and validates the PayPal order and capture amount/currency before it marks
   the invoice paid. Client-provided success statuses are ignored.
7. Use `GET /api/invoices` or `GET /api/invoices/{id}` to read persisted status.

PayPal order creation, capture, and invoice saves have stable idempotency
protection. The app returns to AlvaPay after Sandbox approval; the user must
explicitly choose **Verify payment** to ask the backend to capture and verify
the approved order. The backend currently uses polling during refresh; PayPal
webhooks, reminders, and conversational cash-flow chat remain future work.
The summary endpoint filters verified payment totals on the server before
sending currency-grouped aggregates (without invoice/customer details) to AI.
The Flutter app is wired to the draft, summary, invoice, checkout, capture,
and refresh routes, and stores its session token in platform secure storage.
Anonymous sessions are private per browser/app installation; registering or
signing in moves that installation's invoices to the signed-in account so
they can be accessed from other signed-in devices.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system diagram.

Without provider credentials, the backend deliberately returns a clear
configuration error for AI drafting or PayPal checkout; the app does not
substitute sample AI or payment results. Add sandbox credentials only to
`backend/.env` using [.env.example](.env.example) as a guide. Do not put them in
Flutter build defines or paste them into source files.

## Environment variables

| Variable | Purpose | Default / requirement |
| --- | --- | --- |
| `DATABASE_PATH` | SQLite database location | `./data/alvapay.sqlite3` |
| `CORS_ORIGINS` | Comma-separated exact browser origins | `http://localhost:8080` |
| `PAYPAL_ENV` | Payment environment | `sandbox` only |
| `PAYPAL_CLIENT_ID` | PayPal Sandbox REST app client ID | Required for checkout |
| `PAYPAL_CLIENT_SECRET` | PayPal Sandbox REST app secret | Required for checkout |
| `APP_RETURN_URL` | Return and cancel URL for approved checkout | `http://localhost:8080/` |
| `AI_PROVIDER` | AI integration | `anthropic` (only implemented provider) |
| `AI_MODEL` | Anthropic model ID | `claude-sonnet-5-5` |
| `AI_API_KEY` or `ANTHROPIC_API_KEY` | Anthropic API key | Required for AI drafting |

Create Sandbox REST credentials and a separate buyer test account in the
[PayPal Developer Dashboard](https://developer.paypal.com/tools/sandbox/).
Never use real customer data or production PayPal credentials for this demo.

## Deployment

The API can be deployed to a Python ASGI host and the Flutter Web build to any
HTTPS static-file host. Keep the SQLite file on a persistent disk and run a
single backend instance; this MVP does not configure PostgreSQL or shared
database access.

For a Render Python web service (see Render's
[FastAPI guide](https://render.com/docs/deploy-fastapi),
[web-service guide](https://render.com/docs/web-services), and
[persistent-disk guide](https://render.com/docs/disks)):

1. Push this repository to GitHub or another Git provider and connect it to
   Render. Render detects the root [`render.yaml`](render.yaml) Blueprint.
   Review and deploy the `alvapay-api` service. The Blueprint installs the
   backend, starts Uvicorn on Render's assigned port, and attaches a 1 GB
   persistent disk at `/var/data` for SQLite.
2. In the Render service's Environment settings, set `CORS_ORIGINS` to the
   exact HTTPS origin of the deployed Flutter site (no path or trailing slash)
   and `APP_RETURN_URL` to that site's URL. Add the PayPal Sandbox and
   Anthropic credentials there only if those integrations are to be used.
   Never add credentials to the Blueprint, Flutter build, or repository.
3. Check `https://<your-api-host>/api/health`. For a Flutter Web build, compile
   the public API URL into the client and publish `app/build/web` using a
   static host:

   ```powershell
   Set-Location app
   flutter build web --release --dart-define=API_BASE_URL=https://<your-api-host>
   ```

   `API_BASE_URL` is compiled into the public client, so it must never contain
   a credential. Rebuild the client after changing it.
4. For Android, build and install an APK with that same cloud API URL:

   ```powershell
   Set-Location app
   flutter build apk --release --dart-define=API_BASE_URL=https://<your-api-host>
   ```

   Install `app/build/app/outputs/flutter-apk/app-release.apk` on the phone.
   Unlike the local USB setup, this build does not depend on the development
   computer being on or connected.
5. Verify `/api/health`, then sign in to the cloud service and test the
   workflow with a Sandbox buyer account. The user returns to AlvaPay and
   selects **Verify payment**; payment is not inferred from the redirect.

Render persistent disks require a paid web-service plan. Without a persistent
disk, the SQLite file is lost on restart or redeploy; do not host this MVP on
an ephemeral filesystem if invoice persistence is expected. The cloud database
starts empty: local SQLite records are not automatically copied to it. The
Blueprint prepares the service but does not deploy it until the repository is
connected to a Render account. These instructions do not mean the service has
already been deployed or provider-tested.

## Demo and submission

- [Timed demo script](docs/DEMO_SCRIPT.md)
- [Submission description and implementation notes](docs/SUBMISSION.md)

The live payment portion requires working Sandbox credentials and a Sandbox
buyer account. Until those are configured, demo the user interface with the
automated synthetic tests; do not claim a successful provider payment.

## Security

Keep all PayPal and AI credentials in backend environment variables. Passwords
and session tokens are stored as hashes by the backend; session tokens are
stored in platform secure storage by the app and revoked by logout. Never
commit `.env` files, database files, access tokens, or real customer data.
PayPal integrations are sandbox-only for this project.

## License

AlvaPay is released under the MIT License; see [LICENSE](LICENSE).
