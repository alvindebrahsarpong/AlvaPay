# AlvaPay Demo Script (2:45)

## Before recording

- Start the FastAPI backend and Flutter Web app using the README instructions.
- Configure a valid Anthropic API key and PayPal Sandbox REST app credentials
  in `backend/.env`.
- Create a PayPal Sandbox buyer test account in the
  [PayPal Developer Dashboard](https://developer.paypal.com/tools/sandbox/).
- Confirm the browser can reach the API, and do one complete Sandbox checkout
  rehearsal. Never put credentials or real customer information on screen.
- If a provider is unavailable, explain that it is not configured. Do not
  substitute a fabricated AI draft or payment result.

## Run of show

### 0:00–0:20 — The problem

**Show:** AlvaPay's invoice dashboard.

**Say:** “Freelancers often turn a short project brief into a long sequence of
manual invoice and payment steps. AlvaPay makes the draft faster without
letting AI send a payment request or mark money as paid on its own.”
“Invoices belong to a private email-and-password workspace, and signing out
revokes its backend session.”

### 0:20–0:55 — Draft from a brief

**Show:** Choose **New invoice** and enter a synthetic description, for
example: “Morrow Studio, brand identity project, 840 dollars and 50 cents, due
October 20.”

**Say:** “The backend sends the description to Claude for a schema-constrained
invoice draft. It validates the result again before the app displays it.”

**Action:** Select **Analyze with Alva AI** and wait for the backend response.

### 0:55–1:20 — Human review

**Show:** The editable invoice details and amount.

**Say:** “The draft is not an invoice request yet. I can edit the customer,
description, amount, currency, or due date. The exact amount is saved only
after I review it.”

**Action:** Save the draft, open **Review & send request**, and show the exact
amount in the confirmation sheet. Dismiss it once to demonstrate that
cancelling does not initiate checkout; reopen it and explicitly confirm.

### 1:20–2:05 — PayPal Sandbox approval and verification

**Show:** The app opening the PayPal Sandbox approval page.

**Say:** “Only after that explicit confirmation does the backend create a
Sandbox Orders API order. The browser redirect is not treated as proof of
payment.”

**Action:** Approve using the Sandbox buyer account. Return to AlvaPay and
select **Verify payment**.

**Say:** “The server fetches the order from PayPal, checks its state and exact
amount and currency, and only then records the verified payment.”

### 2:05–2:30 — Show the result

**Show:** The invoice's paid status and dashboard total after the API response.

**Say:** “The status in the app comes from the backend's verified record. If
the provider cannot confirm the capture, the app reports the error instead of
showing a success state.”

**Action:** Open the Alva AI tab and generate a verified cash-flow summary.

**Say:** “For the summary, the server sends Claude only currency-grouped totals
from this session's verified payments. Unpaid invoices and customer details
are excluded.”

### 2:35–2:45 — Close

**Show:** The API diagram or repository.

**Say:** “AlvaPay is Flutter plus FastAPI and SQLite, with provider secrets
kept on the server. The current MVP supports text-based drafting and
PayPal Sandbox checkout. Webhooks, reminders, receipt photos, and
conversational cash-flow chat are not implemented yet.”
