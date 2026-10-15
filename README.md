# AlvaPay

**Split smart. Settle softly.**

AlvaPay helps freelancers turn a plain-language brief into a reviewable invoice
draft, then creates and captures PayPal Sandbox orders only after the user
explicitly confirms the details.

## Project status

Stages 1–2 complete: FastAPI health service and responsive Flutter preview
verified. Invoice drafting currently saves only local drafts; AI and PayPal
checkout are not connected yet.

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

## Build and test

```powershell
Set-Location backend
py -m pytest
ruff check .

Set-Location ..\app
flutter analyze
flutter test
flutter build web
```

## Product and architecture

AlvaPay uses an AI provider to prepare a structured invoice draft from natural
language. People can review and edit the draft before explicit confirmation
creates a PayPal Sandbox checkout order. Payment status is only updated after
server-side verification with PayPal.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the initial system diagram.
Cash-flow summaries are based on verified records stored by the service. Setup,
sandbox walkthrough, deployment, and submission materials will be completed in
later stages.

## Security

Keep all PayPal and AI credentials in backend environment variables. Never
commit `.env` files, database files, access tokens, or real customer data.
PayPal integrations are sandbox-only for this project.

## License

AlvaPay is released under the MIT License; see [LICENSE](LICENSE).
