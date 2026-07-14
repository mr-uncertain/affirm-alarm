# Trial & Billing System Design

**Status:** Approved by user (2026-07-14), split into two sub-projects.

## Purpose

AffirmAlarm is currently a fully on-device iOS app with no accounts, no network
calls, and no backend. This adds a 7-day free trial + paid subscription model:
a new backend/website owns all billing and trial logic, and the iOS app becomes
a thin authenticated client that only ever asks "am I allowed in right now?"

**Guiding principle (hard constraint, not a preference):** all billing/pricing/
subscription logic lives on the backend and website only. The app never
touches payment, pricing, or subscription state directly — it only knows
logged-in-or-not and access-active-or-expired. This is required for Apple App
Store compliance in India (no in-app purchase flow, no pricing UI, no
tappable external payment links on iOS).

## Scope Split

This spec covers two sub-projects with a hard dependency order: B cannot be
built or tested against a real API until A is deployed.

- **Sub-project A — Backend + Website.** New repository, `AffirmAlarm-web`,
  sibling to the existing `AffirmAlarm` repo. Owns the database, auth, trial
  logic, and Razorpay billing. Ships first.
- **Sub-project B — Mobile app integration.** Existing `AffirmAlarm` repo.
  Adds the app's first-ever network dependency: login, status polling, trial
  banner, and the access-expired block screen. Sequenced after A is live.

Each gets its own implementation plan via `superpowers:writing-plans`.

---

## Sub-project A: Backend + Website

### Architecture

Next.js 15 (App Router, TypeScript) deployed on Vercel. Postgres (hosted on
Neon) via Prisma as the ORM. Custom JWT-based auth — not NextAuth — because
the same backend serves two clients (browser + native iOS app), and a plain
bearer-token JWT is the natural fit for a mobile client while NextAuth's
cookie/session model is not. The website sets the JWT as an httpOnly cookie;
the mobile app receives the same JWT in the signup/login response body and
stores it in Keychain, sending it as an `Authorization: Bearer` header.

Razorpay handles all payment collection. The backend never trusts client-side
payment confirmation — subscription activation happens only inside the
signature-verified webhook handler.

### Data Model

`users` table (Prisma schema), extending a standard user record:

```
id                     uuid, primary key
email                  string, unique
password_hash          string (bcrypt)
trial_started_at       timestamp, set at account creation
trial_ends_at          timestamp, = trial_started_at + 7 days
subscription_status    enum: 'trial' | 'active' | 'expired'
subscription_expires_at timestamp, nullable
created_at             timestamp
```

`getSubscriptionStatus(user)`:
- `'trial'` if `now < trial_ends_at`
- `'active'` if `subscription_status === 'active' AND subscription_expires_at > now`
- `'expired'` otherwise

Middleware wraps every authenticated API route: calls `getSubscriptionStatus`,
returns `403 { code: 'ACCESS_EXPIRED' }` if expired, passes through for
`trial`/`active`.

### Pages

| Route | Purpose |
|---|---|
| `/` | Landing page: hero + CTA → `/signup`, features, how-it-works (3 steps), testimonials/placeholder, FAQ, footer (Privacy/Terms/Contact/App Store/Play Store links) |
| `/signup` | Email + password only, "no credit card required" visible, creates account with `trial_status = 'trial'`, redirects to `/download` |
| `/login` | Email + password, redirects to `/account`, links to signup and forgot-password |
| `/download` | Post-signup: "X days remaining", App Store + Play Store buttons, instructions to open the app and log in with the same email |
| `/account` | Protected. Shows email + status. Trial → days remaining + Razorpay plan CTAs. Active → plan name, renewal date, cancel option. Expired → prominent renew CTA. |
| `/account/cancel` | Protected. Confirms cancellation; access continues until `subscription_expires_at`, no renewal after. |
| `/privacy`, `/terms` | Static placeholder content |
| `/forgot-password` | **Scoped down from the original ask:** a static page stating password reset isn't available yet (no email-sending service specified anywhere in this spec) — linked from `/login` so the UI matches the spec, but not a functioning email flow. Flagged explicitly; build the real flow as a follow-up if wanted. |

### API Routes

```
POST /api/auth/signup             creates user + trial fields, returns { token }
POST /api/auth/login               validates credentials, returns { token }
POST /api/auth/logout              clears session cookie (website only)
GET  /api/subscription-status      auth required, returns { status, days_remaining, subscription_expires_at }
POST /api/payment/create-order     auth required, creates Razorpay order, returns { order_id, amount, currency, key_id }
POST /api/payment/webhook          verifies Razorpay signature, activates subscription, idempotent
```

Plan prices (`₹299/month`, `₹2499/year` as placeholders — trivially editable
constants, not hardcoded in multiple places) live in one config module.

### Technical Requirements

- Tailwind CSS, `next/font`
- All protected routes check session server-side; redirect to `/login` if invalid
- Env vars: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `JWT_SECRET`, `DATABASE_URL`
- Razorpay checkout script loaded client-side; order created server-side; **payment is only ever confirmed via the signature-verified webhook**, never trusted from the client redirect/callback
- Mobile-responsive (users land on `/account` from their phone after seeing the app's expired screen)

### Error Handling & Edge Cases

- Reinstall during trial: `trial_started_at` is tied to the account row, not the device — trial continues from the original date on re-login
- Login on a new device post-payment: status check returns `active` immediately (state lives server-side)
- Subscription expires mid-session: next API call returns 403; client (web or app) reacts by re-checking status
- Razorpay webhook fires before the client polls status: no issue — next status check simply returns `active`
- Idempotent webhook: safe to receive the same Razorpay event twice (checked by Razorpay payment/order ID, not blindly re-applied)

### Testing

Given this is genuinely a real DB-mutating auth/billing backend, tests should cover:
- `getSubscriptionStatus` for all three states, including boundary conditions (`now` exactly at `trial_ends_at`)
- Signup sets correct trial fields; login rejects bad credentials
- Middleware returns 403 with the correct body shape for expired users, passes through otherwise
- Webhook signature verification (rejects bad signatures), idempotency (same event applied twice → one activation)
- Cancel sets expiry but doesn't immediately revoke access

---

## Sub-project B: Mobile App Integration

### Architecture

The app gains a lightweight networking layer hitting `GET
/api/subscription-status` on the deployed backend from Sub-project A, a login
screen, and Keychain-backed token storage. No signup UI in the app — account
creation only happens on the website, matching the `/download` page's stated
flow of "download → open → log in with your email."

### Components

- **Login screen**: email + password, calls `POST /api/auth/login`, stores
  returned JWT in Keychain on success
- **Status polling**: calls `/api/subscription-status`
  - on every app launch after login
  - on every foreground event
  - immediately on any 403 from any authenticated call
- **Trial banner**: shown for `'trial'` status — "X day(s) left in your
  trial" using ceiling math (last day shows `1`, never `0`)
- **`AccessExpiredScreen`**: shown for `'expired'` status, blocks all app
  functionality
  - Heading: "Your access has ended"
  - Body: "To continue, visit your account page at:" + plain unstyled text
    URL (`yourapp.com/account`) — **no tappable link, no button, no price
    text on iOS**, per Apple App Store India compliance
  - Android only: the same URL is rendered as a tappable link opening the
    device browser (platform-conditional rendering)
  - No dismiss action — full-screen block

### Error Handling & Edge Cases

- Network failure on a status check: fail open (allow access), retry on next
  foreground event — never lock a user out due to a transient network blip
- `'active'` → no UI change, full access
- Any other status transition follows Sub-project A's edge cases above,
  since the app is a pure reflection of server state

### Testing

- Unit tests for the status-polling logic (mapped response → UI state) using
  a fake networking client, following this codebase's existing fake-based
  testing pattern (see `FakeAIContentService`, `FakeNotificationScheduling`)
  in `Tests/AffirmAlarmCoreTests/Fakes.swift`
- Unit tests for ceiling-day-math on the trial banner (boundary: exactly 1
  day left, exactly 0 days left should still show "1 day left")
- UI test confirming `AccessExpiredScreen` renders no tappable link/button
  on the iOS platform path

---

## Out of Scope (this spec)

- Real email-based password reset (stubbed page only — see `/forgot-password` above)
- Android app changes beyond the one platform-conditional link in `AccessExpiredScreen` (no Android app currently exists in this workspace; Play Store button/link on the website is a placeholder URL until one does)
- Any App Store Connect / Play Store listing work — separate from this feature
- Marketing content quality (testimonials, feature copy) — placeholder-acceptable per the original ask
