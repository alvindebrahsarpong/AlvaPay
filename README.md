# AlvaPay

**Split smart. Settle softly.**

AlvaPay turns a shared expense into a fair, reviewable split, then creates and
tracks PayPal Sandbox invoices after the user explicitly confirms each amount.

## Project status

Milestone 1 complete: monorepo scaffold, backend health service, Flutter app
location, and project documentation.

## Repository layout

```text
alvapay/
|-- app/             Flutter app (Web and Android)
|-- backend/         Node.js, Express, TypeScript API
|-- docs/            Architecture and demo materials
|-- .env.example     Backend configuration template (no credentials)
|-- LICENSE          MIT
`-- README.md
```

## Prerequisites

- Flutter stable with Dart SDK constraints satisfied by `app/pubspec.yaml`.
- Node.js 20.19 or later and npm. **Node.js 20 reached end of life on March 24,
  2026.** This project keeps compatibility with Node 20 per the hackathon
  specification; use a currently supported LTS release for deployment.

## Run locally

1. Copy `.env.example` to `backend/.env` and fill in credentials when ready.
   The Flutter app must never contain backend or provider secrets.
2. Install and run the API:

   ```powershell
   Set-Location backend
   npm install
   npm run dev
   ```

   The API listens on `http://localhost:3000`; check
   `http://localhost:3000/api/health`.
3. In another terminal, run the Flutter app:

   ```powershell
   Set-Location app
   flutter pub get
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
   ```

## Build and test

```powershell
Set-Location backend
npm test
npm run build

Set-Location ..\app
flutter analyze
flutter test
flutter build web
```

## Product and architecture

AlvaPay uses an AI provider to prepare a structured draft from expense text or
a receipt. People can review and edit the split before an explicit confirmation
creates invoices in the PayPal Sandbox. The service records payment status,
supports reminders, and answers questions about saved plans. No invoice is sent
before user confirmation.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the initial system diagram.
Setup, sandbox walkthrough, deployment, and submission materials will be
completed in later milestones.

## Security

Keep all PayPal and LLM credentials in backend environment variables. Never
commit `.env` files, database files, access tokens, or real customer data.
PayPal integrations are sandbox-only for this project.

## License

AlvaPay is released under the MIT License; see [LICENSE](LICENSE).
