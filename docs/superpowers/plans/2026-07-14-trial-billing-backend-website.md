# Trial & Billing Backend + Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Next.js backend + website (Sub-project A of `docs/superpowers/specs/2026-07-14-trial-billing-system-design.md`) that owns all trial/subscription/billing logic: signup, login, a 7-day trial, Razorpay-based paid plans, and a `/api/subscription-status` endpoint the future mobile client will poll.

**Architecture:** Next.js 15 (App Router, TypeScript, Tailwind), Prisma + PostgreSQL, custom JWT auth (httpOnly cookie for the website, same token returned in the response body for the future mobile client), Razorpay for payment collection with webhook-only activation.

**Tech Stack:** Next.js 15, TypeScript, Tailwind CSS, Prisma, PostgreSQL, bcryptjs, jsonwebtoken, razorpay (npm), Vitest.

## Global Constraints

- New repository at `/home/user/Desktop/Vibes/CC-proper/AffirmAlarm-web`, created via `gh repo create`, private, same GitHub account as the existing `AffirmAlarm` repo.
- Before any `git`/`gh` command that touches the remote, run `export GIT_CONFIG_NOSYSTEM=1` first (sandbox workaround for an unreadable `/etc/gitconfig`).
- Package manager: npm. Node 20.
- ORM: Prisma with the `postgresql` provider — this must match production (Neon) exactly. This sandbox has no local Postgres and no running Docker daemon (confirmed: `docker ps` fails to reach the daemon, no `psql`/`postgres` binary installed, no passwordless `sudo` to install one). **Do not attempt to install or start Postgres/Docker locally.** Any test that needs a live database runs only in CI, which provisions a `postgres:16` service container (wired up in Task 2). Locally, `npx prisma generate` (schema→types, no DB connection needed) is sufficient for type-checking.
- Password hashing: `bcryptjs` (pure JS) — not `bcrypt`, to avoid native-binding build issues in CI/sandboxed environments.
- JWT: `jsonwebtoken`, secret from `process.env.JWT_SECRET`, read lazily inside functions (never cached at module load time) so tests can set `process.env.JWT_SECRET` in `beforeAll`.
- Auth token transport: `Authorization: Bearer <token>` header (checked first) OR the `affirmalarm_session` httpOnly cookie (fallback) — this lets the same middleware serve both the website and the future mobile client.
- All billing/pricing/subscription logic stays server-side. Route handlers stay thin; business logic lives in `lib/*.ts` as pure, dependency-injected functions so it's testable without a live DB or a real Razorpay account (fake `UserRepository` / `RazorpayOrderClient` implementations in tests, matching the fake-based testing pattern already used in the `AffirmAlarm` iOS repo's `Tests/AffirmAlarmCoreTests/Fakes.swift`).
- Trial length: 7 days (`TRIAL_DURATION_MS` in `lib/config.ts`). Plans: `monthly` (₹299, 30 days), `annual` (₹2499, 365 days) — both are placeholder prices per the design spec, defined once in `lib/config.ts`, nowhere else.
- Env vars, documented in `.env.example` (no real values committed): `DATABASE_URL`, `JWT_SECRET`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`.
- Payment confirmation happens **only** inside the signature-verified webhook handler — the client-side Razorpay success callback never activates a subscription itself, it only triggers the UI to poll `/api/subscription-status` until it reflects `active`.
- Deploying to Vercel, provisioning the Neon database, and creating the Razorpay merchant account all require credentials only the user has — these are explicitly **not** tasks in this plan. The final task produces a deployment README instead.
- Test runner: Vitest (`npm test` = `vitest run`). Tests live under `tests/`, mirroring the `lib/`/`app/` structure.

---

### Task 1: Project scaffolding, Tailwind, Vitest, CI skeleton, GitHub repo

**Files:**
- Create: entire Next.js project at repo root (`package.json`, `tsconfig.json`, `next.config.ts`, `app/layout.tsx`, `app/page.tsx`, `app/globals.css`, `.gitignore`, `.env.example`)
- Create: `vitest.config.ts`
- Create: `tests/smoke.test.ts`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: the project skeleton every later task builds on. No app-level interfaces yet.

- [ ] **Step 1: Scaffold the Next.js project**

```bash
cd /home/user/Desktop/Vibes/CC-proper
npx create-next-app@latest AffirmAlarm-web \
  --typescript --tailwind --app --no-src-dir --import-alias "@/*" --eslint --use-npm
cd AffirmAlarm-web
```

Accept the defaults it doesn't ask about explicitly via flags.

- [ ] **Step 2: Install remaining dependencies**

```bash
npm install prisma @prisma/client bcryptjs jsonwebtoken razorpay
npm install -D vitest @types/bcryptjs @types/jsonwebtoken
```

- [ ] **Step 3: Add Vitest config**

Create `vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'node',
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
});
```

Add to `package.json` `scripts`:
```json
"test": "vitest run"
```

- [ ] **Step 4: Write and run a smoke test**

Create `tests/smoke.test.ts`:
```ts
import { describe, it, expect } from 'vitest';

describe('project setup', () => {
  it('runs a basic assertion', () => {
    expect(1 + 1).toBe(2);
  });
});
```

Run: `npm test` — expected: 1 passed.

- [ ] **Step 5: Add `.env.example`**

Create `.env.example`:
```
DATABASE_URL=
JWT_SECRET=
RAZORPAY_KEY_ID=
RAZORPAY_KEY_SECRET=
RAZORPAY_WEBHOOK_SECRET=
```

Confirm `.gitignore` (created by `create-next-app`) already excludes `.env*.local` and `node_modules` — it does by default; do not commit `.env.local`.

- [ ] **Step 6: Add CI workflow (no DB yet — added in Task 2)**

Create `.github/workflows/ci.yml`:
```yaml
name: CI
on:
  push:
    branches: ['**']
  pull_request:
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm test
```

- [ ] **Step 7: Confirm the project builds locally**

```bash
npm run build
```
Expected: build succeeds (landing page is the default `create-next-app` placeholder at this point — that's fine, Task 10 replaces it).

- [ ] **Step 8: Create the GitHub repo and push**

```bash
export GIT_CONFIG_NOSYSTEM=1
git init
git add -A
git commit -m "chore: scaffold Next.js project with Tailwind, Vitest, and CI"
gh repo create AffirmAlarm-web --private --source=. --push
```

- [ ] **Step 9: Verify CI is green**

```bash
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```
Expected: lint, build, and test steps all pass.

---

### Task 2: Database schema, Prisma client, CI Postgres service container

**Files:**
- Create: `prisma/schema.prisma`
- Create: `lib/db.ts`
- Create: `lib/config.ts`
- Modify: `.github/workflows/ci.yml`
- Modify: `.env.example`

**Interfaces:**
- Consumes: nothing new.
- Produces: `prisma.User` model (fields: `id`, `email`, `passwordHash`, `trialStartedAt`, `trialEndsAt`, `subscriptionStatus`, `subscriptionExpiresAt`, `createdAt`). `prisma` singleton export from `lib/db.ts`. `TRIAL_DURATION_MS`, `PLANS`, `PlanId` from `lib/config.ts` — every later task that needs trial length or plan pricing imports from here, nowhere else.

- [ ] **Step 1: Write the Prisma schema**

Create `prisma/schema.prisma`:
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum SubscriptionStatus {
  trial
  active
  expired
}

model User {
  id                    String              @id @default(uuid())
  email                 String              @unique
  passwordHash          String
  trialStartedAt        DateTime            @default(now())
  trialEndsAt           DateTime
  subscriptionStatus    SubscriptionStatus  @default(trial)
  subscriptionExpiresAt DateTime?
  createdAt             DateTime            @default(now())
}
```

- [ ] **Step 2: Add the Prisma client singleton**

Create `lib/db.ts`:
```ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
```

- [ ] **Step 3: Add shared config constants**

Create `lib/config.ts`:
```ts
export const TRIAL_DURATION_MS = 7 * 24 * 60 * 60 * 1000;

export type PlanId = 'monthly' | 'annual';

export const PLANS: Record<PlanId, { label: string; priceInPaise: number; durationMs: number }> = {
  monthly: { label: 'Monthly', priceInPaise: 29900, durationMs: 30 * 24 * 60 * 60 * 1000 },
  annual: { label: 'Annual', priceInPaise: 249900, durationMs: 365 * 24 * 60 * 60 * 1000 },
};
```

- [ ] **Step 4: Generate the Prisma client and confirm it type-checks**

```bash
npx prisma generate
npm run build
```
Expected: both succeed without a live `DATABASE_URL` (`prisma generate` only needs the schema file, not a live connection).

- [ ] **Step 5: Wire a Postgres service container into CI and run migrations there**

Replace `.github/workflows/ci.yml` in full:
```yaml
name: CI
on:
  push:
    branches: ['**']
  pull_request:
jobs:
  build-and-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: affirmalarm_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/affirmalarm_test
      JWT_SECRET: ci-test-secret
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
      - run: npm ci
      - run: npx prisma generate
      - run: npx prisma migrate deploy
      - run: npm run lint
      - run: npm run build
      - run: npm test
```

- [ ] **Step 6: Create the initial migration locally (schema-only, no live DB needed for this command)**

```bash
npx prisma migrate dev --name init --create-only
```
This writes `prisma/migrations/<timestamp>_init/migration.sql` from the schema diff without needing a reachable database (`--create-only` skips applying it). Inspect the generated SQL file to confirm it creates the `User` table and `SubscriptionStatus` enum as expected.

- [ ] **Step 7: Update `.env.example`**

`.env.example` already lists `DATABASE_URL` from Task 1 — no change needed; confirm it's still there.

- [ ] **Step 8: Commit and push**

```bash
git add prisma lib/db.ts lib/config.ts .github/workflows/ci.yml
git commit -m "feat: add Prisma schema, DB client, and shared config; wire Postgres into CI"
git push
```

- [ ] **Step 9: Verify CI is green**

```bash
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```
Expected: `prisma migrate deploy` applies the migration against the service container, all subsequent steps pass.

---

### Task 3: Password hashing and JWT helpers

**Files:**
- Create: `lib/auth.ts`
- Test: `tests/lib/auth.test.ts`

**Interfaces:**
- Consumes: nothing new.
- Produces: `hashPassword(password): Promise<string>`, `verifyPassword(password, hash): Promise<boolean>`, `signToken({userId, email}): string`, `verifyToken(token): TokenPayload | null`, `TokenPayload` type. Used by Tasks 5 and 6.

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/auth.test.ts`:
```ts
import { describe, it, expect, beforeAll } from 'vitest';
import { hashPassword, verifyPassword, signToken, verifyToken } from '../../lib/auth';

beforeAll(() => {
  process.env.JWT_SECRET = 'test-secret';
});

describe('password hashing', () => {
  it('hashes and verifies a correct password', async () => {
    const hash = await hashPassword('correct-horse');
    expect(await verifyPassword('correct-horse', hash)).toBe(true);
  });

  it('rejects an incorrect password', async () => {
    const hash = await hashPassword('correct-horse');
    expect(await verifyPassword('wrong-password', hash)).toBe(false);
  });
});

describe('JWT tokens', () => {
  it('round-trips a valid token', () => {
    const token = signToken({ userId: 'abc123', email: 'a@b.com' });
    const payload = verifyToken(token);
    expect(payload?.userId).toBe('abc123');
    expect(payload?.email).toBe('a@b.com');
  });

  it('returns null for a tampered token', () => {
    const token = signToken({ userId: 'abc123', email: 'a@b.com' });
    expect(verifyToken(token + 'x')).toBeNull();
  });

  it('returns null for a token signed with a different secret', () => {
    const token = signToken({ userId: 'abc123', email: 'a@b.com' });
    process.env.JWT_SECRET = 'a-different-secret';
    expect(verifyToken(token)).toBeNull();
    process.env.JWT_SECRET = 'test-secret';
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/lib/auth.test.ts`
Expected: FAIL — `lib/auth.ts` does not exist.

- [ ] **Step 3: Implement the helpers**

Create `lib/auth.ts`:
```ts
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

const TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

export interface TokenPayload {
  userId: string;
  email: string;
}

function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET is not set');
  return secret;
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 10);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, getJwtSecret(), { expiresIn: TOKEN_TTL_SECONDS });
}

export function verifyToken(token: string): TokenPayload | null {
  try {
    return jwt.verify(token, getJwtSecret()) as TokenPayload;
  } catch {
    return null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/lib/auth.test.ts`
Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/auth.ts tests/lib/auth.test.ts
git commit -m "feat: add password hashing and JWT helpers"
git push
```

---

### Task 4: Subscription status logic

**Files:**
- Create: `lib/subscription.ts`
- Test: `tests/lib/subscription.test.ts`

**Interfaces:**
- Consumes: `TRIAL_DURATION_MS` from `lib/config.ts` (Task 2) — not directly used in this file's logic (trial length is applied at signup, Task 6) but the file's `SubscriptionFields` shape matches the `User` model's relevant fields.
- Produces: `getSubscriptionStatus(user, now?): 'trial' | 'active' | 'expired'`, `daysRemaining(trialEndsAt, now?): number`. Used by Tasks 5 and 7.

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/subscription.test.ts`:
```ts
import { describe, it, expect } from 'vitest';
import { getSubscriptionStatus, daysRemaining } from '../../lib/subscription';

describe('getSubscriptionStatus', () => {
  const now = new Date('2026-01-08T00:00:00Z');

  it('returns trial when now is before trialEndsAt', () => {
    const status = getSubscriptionStatus(
      { trialEndsAt: new Date('2026-01-09T00:00:00Z'), subscriptionStatus: 'trial', subscriptionExpiresAt: null },
      now
    );
    expect(status).toBe('trial');
  });

  it('returns expired exactly at trialEndsAt with no active subscription', () => {
    const status = getSubscriptionStatus(
      { trialEndsAt: now, subscriptionStatus: 'trial', subscriptionExpiresAt: null },
      now
    );
    expect(status).toBe('expired');
  });

  it('returns active when subscription is active and not yet expired', () => {
    const status = getSubscriptionStatus(
      {
        trialEndsAt: new Date('2025-01-01T00:00:00Z'),
        subscriptionStatus: 'active',
        subscriptionExpiresAt: new Date('2026-02-01T00:00:00Z'),
      },
      now
    );
    expect(status).toBe('active');
  });

  it('returns expired when subscription is active but past its expiry', () => {
    const status = getSubscriptionStatus(
      {
        trialEndsAt: new Date('2025-01-01T00:00:00Z'),
        subscriptionStatus: 'active',
        subscriptionExpiresAt: new Date('2026-01-01T00:00:00Z'),
      },
      now
    );
    expect(status).toBe('expired');
  });

  it('returns expired when trial has ended and subscription was never activated', () => {
    const status = getSubscriptionStatus(
      { trialEndsAt: new Date('2025-01-01T00:00:00Z'), subscriptionStatus: 'trial', subscriptionExpiresAt: null },
      now
    );
    expect(status).toBe('expired');
  });
});

describe('daysRemaining', () => {
  it('shows 1 on the last day, not 0', () => {
    const trialEndsAt = new Date('2026-01-08T01:00:00Z');
    const now = new Date('2026-01-08T00:00:00Z');
    expect(daysRemaining(trialEndsAt, now)).toBe(1);
  });

  it('rounds up partial days', () => {
    const trialEndsAt = new Date('2026-01-10T12:00:00Z');
    const now = new Date('2026-01-08T00:00:00Z');
    expect(daysRemaining(trialEndsAt, now)).toBe(3);
  });

  it('returns 0 once trialEndsAt has passed', () => {
    const trialEndsAt = new Date('2026-01-01T00:00:00Z');
    const now = new Date('2026-01-08T00:00:00Z');
    expect(daysRemaining(trialEndsAt, now)).toBe(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/lib/subscription.test.ts`
Expected: FAIL — `lib/subscription.ts` does not exist.

- [ ] **Step 3: Implement**

Create `lib/subscription.ts`:
```ts
export type SubscriptionStatusValue = 'trial' | 'active' | 'expired';

export interface SubscriptionFields {
  trialEndsAt: Date;
  subscriptionStatus: 'trial' | 'active' | 'expired';
  subscriptionExpiresAt: Date | null;
}

export function getSubscriptionStatus(user: SubscriptionFields, now: Date = new Date()): SubscriptionStatusValue {
  if (now < user.trialEndsAt) return 'trial';
  if (user.subscriptionStatus === 'active' && user.subscriptionExpiresAt && user.subscriptionExpiresAt > now) {
    return 'active';
  }
  return 'expired';
}

export function daysRemaining(trialEndsAt: Date, now: Date = new Date()): number {
  const msRemaining = trialEndsAt.getTime() - now.getTime();
  if (msRemaining <= 0) return 0;
  return Math.ceil(msRemaining / (24 * 60 * 60 * 1000));
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/lib/subscription.test.ts`
Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/subscription.ts tests/lib/subscription.test.ts
git commit -m "feat: add subscription status derivation and trial days-remaining math"
git push
```

---

### Task 5: User repository abstraction and the `withAuth` request wrapper

**Files:**
- Create: `lib/userRepository.ts`
- Create: `lib/withAuth.ts`
- Test: `tests/lib/withAuth.test.ts`

**Interfaces:**
- Consumes: `getSubscriptionStatus` (Task 4), `verifyToken` (Task 3), `prisma` (Task 2).
- Produces: `UserRepository` interface + `prismaUserRepository` implementation, `withAuth(handler, repo?)`, `SESSION_COOKIE_NAME` constant. Every authenticated API route (Tasks 6, 7, 8, 9) wraps its handler in `withAuth`.

- [ ] **Step 1: Write the repository abstraction**

Create `lib/userRepository.ts`:
```ts
import { prisma } from './db';
import type { User } from '@prisma/client';

export interface UserRepository {
  findById(id: string): Promise<User | null>;
  findByEmail(email: string): Promise<User | null>;
  create(data: {
    email: string;
    passwordHash: string;
    trialStartedAt: Date;
    trialEndsAt: Date;
  }): Promise<User>;
  activateSubscription(id: string, expiresAt: Date): Promise<User>;
}

export const prismaUserRepository: UserRepository = {
  findById: (id) => prisma.user.findUnique({ where: { id } }),
  findByEmail: (email) => prisma.user.findUnique({ where: { email } }),
  create: (data) => prisma.user.create({ data: { ...data, subscriptionStatus: 'trial' } }),
  activateSubscription: (id, expiresAt) =>
    prisma.user.update({
      where: { id },
      data: { subscriptionStatus: 'active', subscriptionExpiresAt: expiresAt },
    }),
};
```

- [ ] **Step 2: Write the failing tests for `withAuth`**

Create `tests/lib/withAuth.test.ts`:
```ts
import { describe, it, expect, beforeAll, vi } from 'vitest';
import { NextRequest, NextResponse } from 'next/server';
import { withAuth } from '../../lib/withAuth';
import { signToken } from '../../lib/auth';
import type { UserRepository } from '../../lib/userRepository';
import type { User } from '@prisma/client';

beforeAll(() => {
  process.env.JWT_SECRET = 'test-secret';
});

function makeFakeRepo(user: User | null): UserRepository {
  return {
    findById: vi.fn(async () => user),
    findByEmail: vi.fn(async () => user),
    create: vi.fn(),
    activateSubscription: vi.fn(),
  };
}

function makeUser(overrides: Partial<User> = {}): User {
  return {
    id: 'user-1',
    email: 'a@b.com',
    passwordHash: 'x',
    trialStartedAt: new Date('2025-01-01'),
    trialEndsAt: new Date('2099-01-01'),
    subscriptionStatus: 'trial',
    subscriptionExpiresAt: null,
    createdAt: new Date('2025-01-01'),
    ...overrides,
  };
}

describe('withAuth', () => {
  it('returns 401 with no token', async () => {
    const handler = withAuth(async () => NextResponse.json({ ok: true }), makeFakeRepo(null));
    const res = await handler(new NextRequest('http://localhost/api/test'));
    expect(res.status).toBe(401);
  });

  it('returns 401 with an invalid token', async () => {
    const handler = withAuth(async () => NextResponse.json({ ok: true }), makeFakeRepo(null));
    const res = await handler(
      new NextRequest('http://localhost/api/test', { headers: { authorization: 'Bearer garbage' } })
    );
    expect(res.status).toBe(401);
  });

  it('returns 403 ACCESS_EXPIRED for an expired user', async () => {
    const user = makeUser({ trialEndsAt: new Date('2020-01-01'), subscriptionStatus: 'trial' });
    const token = signToken({ userId: user.id, email: user.email });
    const handler = withAuth(async () => NextResponse.json({ ok: true }), makeFakeRepo(user));
    const res = await handler(
      new NextRequest('http://localhost/api/test', { headers: { authorization: `Bearer ${token}` } })
    );
    expect(res.status).toBe(403);
    expect((await res.json()).code).toBe('ACCESS_EXPIRED');
  });

  it('passes through to the handler for a trial user, reading the token from the Authorization header', async () => {
    const user = makeUser();
    const token = signToken({ userId: user.id, email: user.email });
    const handler = withAuth(async (_req, u) => NextResponse.json({ email: u.email }), makeFakeRepo(user));
    const res = await handler(
      new NextRequest('http://localhost/api/test', { headers: { authorization: `Bearer ${token}` } })
    );
    expect(res.status).toBe(200);
    expect((await res.json()).email).toBe('a@b.com');
  });

  it('passes through for a trial user, reading the token from the session cookie', async () => {
    const user = makeUser();
    const token = signToken({ userId: user.id, email: user.email });
    const handler = withAuth(async (_req, u) => NextResponse.json({ email: u.email }), makeFakeRepo(user));
    const res = await handler(
      new NextRequest('http://localhost/api/test', { headers: { cookie: `affirmalarm_session=${token}` } })
    );
    expect(res.status).toBe(200);
    expect((await res.json()).email).toBe('a@b.com');
  });

  it('passes through for an active (paid) user', async () => {
    const user = makeUser({
      trialEndsAt: new Date('2020-01-01'),
      subscriptionStatus: 'active',
      subscriptionExpiresAt: new Date('2099-01-01'),
    });
    const token = signToken({ userId: user.id, email: user.email });
    const handler = withAuth(async (_req, u) => NextResponse.json({ email: u.email }), makeFakeRepo(user));
    const res = await handler(
      new NextRequest('http://localhost/api/test', { headers: { authorization: `Bearer ${token}` } })
    );
    expect(res.status).toBe(200);
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npm test -- tests/lib/withAuth.test.ts`
Expected: FAIL — `lib/withAuth.ts` does not exist.

- [ ] **Step 4: Implement `withAuth`**

Create `lib/withAuth.ts`:
```ts
import { NextRequest, NextResponse } from 'next/server';
import { verifyToken } from './auth';
import { getSubscriptionStatus } from './subscription';
import { prismaUserRepository, type UserRepository } from './userRepository';
import type { User } from '@prisma/client';

export const SESSION_COOKIE_NAME = 'affirmalarm_session';

export type AuthedHandler = (req: NextRequest, user: User) => Promise<NextResponse>;

function extractToken(req: NextRequest): string | null {
  const authHeader = req.headers.get('authorization');
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.slice('Bearer '.length);
  }
  return req.cookies.get(SESSION_COOKIE_NAME)?.value ?? null;
}

export function withAuth(handler: AuthedHandler, repo: UserRepository = prismaUserRepository) {
  return async (req: NextRequest): Promise<NextResponse> => {
    const token = extractToken(req);
    if (!token) {
      return NextResponse.json({ code: 'UNAUTHENTICATED' }, { status: 401 });
    }

    const payload = verifyToken(token);
    if (!payload) {
      return NextResponse.json({ code: 'UNAUTHENTICATED' }, { status: 401 });
    }

    const user = await repo.findById(payload.userId);
    if (!user) {
      return NextResponse.json({ code: 'UNAUTHENTICATED' }, { status: 401 });
    }

    const status = getSubscriptionStatus(user);
    if (status === 'expired') {
      return NextResponse.json({ code: 'ACCESS_EXPIRED' }, { status: 403 });
    }

    return handler(req, user);
  };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npm test -- tests/lib/withAuth.test.ts`
Expected: all 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/userRepository.ts lib/withAuth.ts tests/lib/withAuth.test.ts
git commit -m "feat: add user repository abstraction and the withAuth request wrapper"
git push
```

---

### Task 6: Signup, login, and logout

**Files:**
- Create: `lib/authActions.ts`
- Create: `app/api/auth/signup/route.ts`
- Create: `app/api/auth/login/route.ts`
- Create: `app/api/auth/logout/route.ts`
- Test: `tests/lib/authActions.test.ts`

**Interfaces:**
- Consumes: `UserRepository` (Task 5), `hashPassword`/`verifyPassword`/`signToken` (Task 3), `TRIAL_DURATION_MS` (Task 2), `SESSION_COOKIE_NAME` (Task 5).
- Produces: `signupUser(repo, email, password, now?)`, `loginUser(repo, email, password)` — pure, DB-agnostic, used directly by the three route handlers.

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/authActions.test.ts`:
```ts
import { describe, it, expect, beforeAll, vi } from 'vitest';
import { signupUser, loginUser } from '../../lib/authActions';
import { hashPassword } from '../../lib/auth';
import type { UserRepository } from '../../lib/userRepository';
import type { User } from '@prisma/client';

beforeAll(() => {
  process.env.JWT_SECRET = 'test-secret';
});

function makeRepo(overrides: Partial<UserRepository> = {}): UserRepository {
  return {
    findById: vi.fn(async () => null),
    findByEmail: vi.fn(async () => null),
    create: vi.fn(async (data) => ({
      id: 'new-user',
      email: data.email,
      passwordHash: data.passwordHash,
      trialStartedAt: data.trialStartedAt,
      trialEndsAt: data.trialEndsAt,
      subscriptionStatus: 'trial',
      subscriptionExpiresAt: null,
      createdAt: data.trialStartedAt,
    })),
    activateSubscription: vi.fn(),
    ...overrides,
  };
}

describe('signupUser', () => {
  it('creates a user with trial fields set 7 days out and returns a token', async () => {
    const repo = makeRepo();
    const now = new Date('2026-01-01T00:00:00Z');
    const result = await signupUser(repo, 'new@user.com', 'password123', now);

    expect(result.ok).toBe(true);
    expect(repo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        email: 'new@user.com',
        trialStartedAt: now,
        trialEndsAt: new Date('2026-01-08T00:00:00Z'),
      })
    );
  });

  it('rejects signup when the email is already registered', async () => {
    const repo = makeRepo({
      findByEmail: vi.fn(async () => ({ id: 'existing' }) as User),
    });
    const result = await signupUser(repo, 'taken@user.com', 'password123');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toMatch(/already exists/i);
    expect(repo.create).not.toHaveBeenCalled();
  });
});

describe('loginUser', () => {
  it('returns a token for correct credentials', async () => {
    const passwordHash = await hashPassword('correct-password');
    const repo = makeRepo({
      findByEmail: vi.fn(
        async () =>
          ({
            id: 'user-1',
            email: 'a@b.com',
            passwordHash,
          }) as User
      ),
    });
    const result = await loginUser(repo, 'a@b.com', 'correct-password');
    expect(result.ok).toBe(true);
  });

  it('rejects an unknown email', async () => {
    const repo = makeRepo();
    const result = await loginUser(repo, 'nobody@user.com', 'whatever');
    expect(result.ok).toBe(false);
  });

  it('rejects a wrong password without revealing whether the email exists', async () => {
    const passwordHash = await hashPassword('correct-password');
    const repo = makeRepo({
      findByEmail: vi.fn(async () => ({ id: 'user-1', email: 'a@b.com', passwordHash }) as User),
    });
    const wrongPasswordResult = await loginUser(repo, 'a@b.com', 'wrong');
    const unknownEmailResult = await loginUser(repo, 'nobody@user.com', 'whatever');
    expect(wrongPasswordResult.ok).toBe(false);
    expect(unknownEmailResult.ok).toBe(false);
    if (!wrongPasswordResult.ok && !unknownEmailResult.ok) {
      expect(wrongPasswordResult.error).toBe(unknownEmailResult.error);
    }
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/lib/authActions.test.ts`
Expected: FAIL — `lib/authActions.ts` does not exist.

- [ ] **Step 3: Implement `lib/authActions.ts`**

```ts
import { hashPassword, verifyPassword, signToken } from './auth';
import { TRIAL_DURATION_MS } from './config';
import type { UserRepository } from './userRepository';

export type SignupResult = { ok: true; token: string } | { ok: false; error: string };
export type LoginResult = { ok: true; token: string } | { ok: false; error: string };

const INVALID_CREDENTIALS_MESSAGE = 'Invalid email or password.';

export async function signupUser(
  repo: UserRepository,
  email: string,
  password: string,
  now: Date = new Date()
): Promise<SignupResult> {
  const existing = await repo.findByEmail(email);
  if (existing) {
    return { ok: false, error: 'An account with this email already exists.' };
  }

  const passwordHash = await hashPassword(password);
  const trialStartedAt = now;
  const trialEndsAt = new Date(now.getTime() + TRIAL_DURATION_MS);

  const user = await repo.create({ email, passwordHash, trialStartedAt, trialEndsAt });
  const token = signToken({ userId: user.id, email: user.email });
  return { ok: true, token };
}

export async function loginUser(repo: UserRepository, email: string, password: string): Promise<LoginResult> {
  const user = await repo.findByEmail(email);
  if (!user) {
    return { ok: false, error: INVALID_CREDENTIALS_MESSAGE };
  }
  const valid = await verifyPassword(password, user.passwordHash);
  if (!valid) {
    return { ok: false, error: INVALID_CREDENTIALS_MESSAGE };
  }
  const token = signToken({ userId: user.id, email: user.email });
  return { ok: true, token };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/lib/authActions.test.ts`
Expected: all 5 tests pass.

- [ ] **Step 5: Implement the three route handlers**

Create `app/api/auth/signup/route.ts`:
```ts
import { NextRequest, NextResponse } from 'next/server';
import { signupUser } from '@/lib/authActions';
import { prismaUserRepository } from '@/lib/userRepository';
import { SESSION_COOKIE_NAME } from '@/lib/withAuth';

export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (!email || !password) {
    return NextResponse.json({ error: 'Email and password are required.' }, { status: 400 });
  }

  const result = await signupUser(prismaUserRepository, email, password);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 409 });
  }

  const res = NextResponse.json({ token: result.token });
  res.cookies.set(SESSION_COOKIE_NAME, result.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 24 * 30,
  });
  return res;
}
```

Create `app/api/auth/login/route.ts`:
```ts
import { NextRequest, NextResponse } from 'next/server';
import { loginUser } from '@/lib/authActions';
import { prismaUserRepository } from '@/lib/userRepository';
import { SESSION_COOKIE_NAME } from '@/lib/withAuth';

export async function POST(req: NextRequest) {
  const { email, password } = await req.json();
  if (!email || !password) {
    return NextResponse.json({ error: 'Email and password are required.' }, { status: 400 });
  }

  const result = await loginUser(prismaUserRepository, email, password);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 401 });
  }

  const res = NextResponse.json({ token: result.token });
  res.cookies.set(SESSION_COOKIE_NAME, result.token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
    maxAge: 60 * 60 * 24 * 30,
  });
  return res;
}
```

Create `app/api/auth/logout/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { SESSION_COOKIE_NAME } from '@/lib/withAuth';

export async function POST() {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(SESSION_COOKIE_NAME);
  return res;
}
```

- [ ] **Step 6: Push and verify on CI**

```bash
git add lib/authActions.ts app/api/auth tests/lib/authActions.test.ts
git commit -m "feat: add signup, login, and logout routes"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```
Expected: all steps pass.

---

### Task 7: `GET /api/subscription-status`

**Files:**
- Create: `app/api/subscription-status/route.ts`
- Test: `tests/app/subscription-status.test.ts`

**Interfaces:**
- Consumes: `withAuth` (Task 5), `getSubscriptionStatus`/`daysRemaining` (Task 4). This is the exact endpoint the future mobile app (Sub-project B) polls.
- Produces: `GET` handler returning `{ status, days_remaining, subscription_expires_at }`.

- [ ] **Step 1: Write the failing test**

Create `tests/app/subscription-status.test.ts`:
```ts
import { describe, it, expect, beforeAll, vi } from 'vitest';
import { NextRequest } from 'next/server';
import { GET } from '../../app/api/subscription-status/route';
import { signToken } from '../../lib/auth';
import * as userRepository from '../../lib/userRepository';
import type { User } from '@prisma/client';

beforeAll(() => {
  process.env.JWT_SECRET = 'test-secret';
});

function makeUser(overrides: Partial<User> = {}): User {
  return {
    id: 'user-1',
    email: 'a@b.com',
    passwordHash: 'x',
    trialStartedAt: new Date('2026-01-01T00:00:00Z'),
    trialEndsAt: new Date('2026-01-08T00:00:00Z'),
    subscriptionStatus: 'trial',
    subscriptionExpiresAt: null,
    createdAt: new Date('2026-01-01T00:00:00Z'),
    ...overrides,
  };
}

describe('GET /api/subscription-status', () => {
  it('returns trial status with days_remaining', async () => {
    const user = makeUser();
    vi.spyOn(userRepository.prismaUserRepository, 'findById').mockResolvedValue(user);
    const token = signToken({ userId: user.id, email: user.email });
    const req = new NextRequest('http://localhost/api/subscription-status', {
      headers: { authorization: `Bearer ${token}` },
    });
    const res = await GET(req);
    const body = await res.json();
    expect(body.status).toBe('trial');
    expect(typeof body.days_remaining).toBe('number');
    expect(body.days_remaining).toBeGreaterThan(0);
  });

  it('returns active status with days_remaining of 0 (not applicable to a paid plan)', async () => {
    const user = makeUser({
      trialEndsAt: new Date('2020-01-01T00:00:00Z'),
      subscriptionStatus: 'active',
      subscriptionExpiresAt: new Date('2099-01-01T00:00:00Z'),
    });
    vi.spyOn(userRepository.prismaUserRepository, 'findById').mockResolvedValue(user);
    const token = signToken({ userId: user.id, email: user.email });
    const req = new NextRequest('http://localhost/api/subscription-status', {
      headers: { authorization: `Bearer ${token}` },
    });
    const res = await GET(req);
    const body = await res.json();
    expect(body.status).toBe('active');
    expect(body.days_remaining).toBe(0);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/app/subscription-status.test.ts`
Expected: FAIL — `app/api/subscription-status/route.ts` does not exist.

- [ ] **Step 3: Implement**

Create `app/api/subscription-status/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { withAuth } from '@/lib/withAuth';
import { getSubscriptionStatus, daysRemaining } from '@/lib/subscription';

export const GET = withAuth(async (_req, user) => {
  const status = getSubscriptionStatus(user);
  return NextResponse.json({
    status,
    days_remaining: status === 'trial' ? daysRemaining(user.trialEndsAt) : 0,
    subscription_expires_at: user.subscriptionExpiresAt,
  });
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/app/subscription-status.test.ts`
Expected: both tests pass.

- [ ] **Step 5: Push and verify on CI**

```bash
git add app/api/subscription-status tests/app/subscription-status.test.ts
git commit -m "feat: add GET /api/subscription-status"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 8: Razorpay order creation

**Files:**
- Create: `lib/razorpay.ts`
- Create: `lib/paymentActions.ts`
- Create: `app/api/payment/create-order/route.ts`
- Test: `tests/lib/paymentActions.test.ts`

**Interfaces:**
- Consumes: `PLANS`/`PlanId` (Task 2), `withAuth` (Task 5).
- Produces: `RazorpayOrderClient` interface + `realRazorpayOrderClient`, `createOrderForPlan(client, planId, userId)`. Task 9's webhook relies on the `notes: { userId, planId }` this task attaches to every order.

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/paymentActions.test.ts`:
```ts
import { describe, it, expect, vi } from 'vitest';
import { createOrderForPlan } from '../../lib/paymentActions';
import type { RazorpayOrderClient } from '../../lib/razorpay';

function makeFakeClient(): RazorpayOrderClient & { createOrder: ReturnType<typeof vi.fn> } {
  return {
    createOrder: vi.fn(async () => ({ id: 'order_fake123' })),
  };
}

describe('createOrderForPlan', () => {
  it('creates an order with the monthly plan price and attaches userId/planId notes', async () => {
    const client = makeFakeClient();
    const result = await createOrderForPlan(client, 'monthly', 'user-1');

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.orderId).toBe('order_fake123');
      expect(result.amount).toBe(29900);
      expect(result.currency).toBe('INR');
    }
    expect(client.createOrder).toHaveBeenCalledWith(
      29900,
      'INR',
      expect.any(String),
      { userId: 'user-1', planId: 'monthly' }
    );
  });

  it('creates an order with the annual plan price', async () => {
    const client = makeFakeClient();
    const result = await createOrderForPlan(client, 'annual', 'user-1');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.amount).toBe(249900);
  });

  it('rejects an unknown plan id without calling the client', async () => {
    const client = makeFakeClient();
    const result = await createOrderForPlan(client, 'lifetime', 'user-1');
    expect(result.ok).toBe(false);
    expect(client.createOrder).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/lib/paymentActions.test.ts`
Expected: FAIL — neither file exists yet.

- [ ] **Step 3: Implement `lib/razorpay.ts`**

```ts
import Razorpay from 'razorpay';

let client: Razorpay | null = null;

function getRazorpayClient(): Razorpay {
  if (!client) {
    client = new Razorpay({
      key_id: process.env.RAZORPAY_KEY_ID!,
      key_secret: process.env.RAZORPAY_KEY_SECRET!,
    });
  }
  return client;
}

export interface RazorpayOrderClient {
  createOrder(
    amountInPaise: number,
    currency: string,
    receipt: string,
    notes: Record<string, string>
  ): Promise<{ id: string }>;
}

export const realRazorpayOrderClient: RazorpayOrderClient = {
  async createOrder(amountInPaise, currency, receipt, notes) {
    const order = await getRazorpayClient().orders.create({ amount: amountInPaise, currency, receipt, notes });
    return { id: order.id };
  },
};
```

- [ ] **Step 4: Implement `lib/paymentActions.ts`**

```ts
import { PLANS, type PlanId } from './config';
import type { RazorpayOrderClient } from './razorpay';

export type CreateOrderResult =
  | { ok: true; orderId: string; amount: number; currency: string }
  | { ok: false; error: string };

export async function createOrderForPlan(
  client: RazorpayOrderClient,
  planId: string,
  userId: string
): Promise<CreateOrderResult> {
  const plan = PLANS[planId as PlanId];
  if (!plan) {
    return { ok: false, error: 'Unknown plan.' };
  }
  const order = await client.createOrder(plan.priceInPaise, 'INR', `${userId}-${planId}-${Date.now()}`, {
    userId,
    planId,
  });
  return { ok: true, orderId: order.id, amount: plan.priceInPaise, currency: 'INR' };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npm test -- tests/lib/paymentActions.test.ts`
Expected: all 3 tests pass.

- [ ] **Step 6: Implement the route**

Create `app/api/payment/create-order/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { withAuth } from '@/lib/withAuth';
import { createOrderForPlan } from '@/lib/paymentActions';
import { realRazorpayOrderClient } from '@/lib/razorpay';

export const POST = withAuth(async (req, user) => {
  const { planId } = await req.json();
  const result = await createOrderForPlan(realRazorpayOrderClient, planId, user.id);
  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: 400 });
  }
  return NextResponse.json({
    order_id: result.orderId,
    amount: result.amount,
    currency: result.currency,
    key_id: process.env.RAZORPAY_KEY_ID,
  });
});
```

- [ ] **Step 7: Push and verify on CI**

```bash
git add lib/razorpay.ts lib/paymentActions.ts app/api/payment/create-order tests/lib/paymentActions.test.ts
git commit -m "feat: add Razorpay order creation"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 9: Razorpay webhook — signature verification, idempotent activation

**Files:**
- Create: `lib/webhookHandler.ts`
- Create: `app/api/payment/webhook/route.ts`
- Test: `tests/lib/webhookHandler.test.ts`

**Interfaces:**
- Consumes: `UserRepository` (Task 5), `PLANS`/`PlanId` (Task 2). Reads the `notes: { userId, planId }` that Task 8 attaches to every order, echoed back on `payload.order.entity.notes` in the Razorpay webhook payload.
- Produces: `verifyWebhookSignature(rawBody, signature, secret): boolean`, `handleWebhookEvent(repo, body, now?): Promise<{handled: boolean}>`.

- [ ] **Step 1: Write the failing tests**

Create `tests/lib/webhookHandler.test.ts`:
```ts
import { describe, it, expect, vi } from 'vitest';
import crypto from 'crypto';
import { verifyWebhookSignature, handleWebhookEvent } from '../../lib/webhookHandler';
import type { UserRepository } from '../../lib/userRepository';

function sign(body: string, secret: string): string {
  return crypto.createHmac('sha256', secret).update(body).digest('hex');
}

describe('verifyWebhookSignature', () => {
  it('accepts a correctly signed payload', () => {
    const body = JSON.stringify({ event: 'payment.captured' });
    const signature = sign(body, 'whsecret');
    expect(verifyWebhookSignature(body, signature, 'whsecret')).toBe(true);
  });

  it('rejects a payload with a bad signature', () => {
    const body = JSON.stringify({ event: 'payment.captured' });
    expect(verifyWebhookSignature(body, 'not-the-right-signature-not-the-right-signature', 'whsecret')).toBe(false);
  });
});

describe('handleWebhookEvent', () => {
  function makeRepo(): UserRepository {
    return {
      findById: vi.fn(),
      findByEmail: vi.fn(),
      create: vi.fn(),
      activateSubscription: vi.fn(async (id, expiresAt) => ({ id }) as any),
    };
  }

  it('activates the subscription for a payment.captured event with valid notes', async () => {
    const repo = makeRepo();
    const now = new Date('2026-01-01T00:00:00Z');
    const result = await handleWebhookEvent(
      repo,
      {
        event: 'payment.captured',
        payload: { order: { entity: { notes: { userId: 'user-1', planId: 'monthly' } } } },
      },
      now
    );
    expect(result.handled).toBe(true);
    expect(repo.activateSubscription).toHaveBeenCalledWith('user-1', new Date('2026-01-31T00:00:00Z'));
  });

  it('ignores events other than payment.captured', async () => {
    const repo = makeRepo();
    const result = await handleWebhookEvent(repo, {
      event: 'payment.failed',
      payload: { order: { entity: { notes: { userId: 'user-1', planId: 'monthly' } } } },
    });
    expect(result.handled).toBe(false);
    expect(repo.activateSubscription).not.toHaveBeenCalled();
  });

  it('is idempotent: applying the same event twice does not stack extra duration', async () => {
    const repo = makeRepo();
    const now = new Date('2026-01-01T00:00:00Z');
    const event = {
      event: 'payment.captured' as const,
      payload: { order: { entity: { notes: { userId: 'user-1', planId: 'monthly' } } } },
    };
    await handleWebhookEvent(repo, event, now);
    await handleWebhookEvent(repo, event, now);
    expect(repo.activateSubscription).toHaveBeenCalledTimes(2);
    const calls = (repo.activateSubscription as any).mock.calls;
    expect(calls[0]).toEqual(calls[1]);
  });

  it('does not activate when notes are missing userId or planId', async () => {
    const repo = makeRepo();
    const result = await handleWebhookEvent(repo, {
      event: 'payment.captured',
      payload: { order: { entity: { notes: {} } } },
    });
    expect(result.handled).toBe(false);
    expect(repo.activateSubscription).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/lib/webhookHandler.test.ts`
Expected: FAIL — `lib/webhookHandler.ts` does not exist.

- [ ] **Step 3: Implement**

Create `lib/webhookHandler.ts`:
```ts
import crypto from 'crypto';
import { PLANS, type PlanId } from './config';
import type { UserRepository } from './userRepository';

export function verifyWebhookSignature(rawBody: string, signature: string, secret: string): boolean {
  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  if (expected.length !== signature.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

interface RazorpayWebhookPayload {
  event: string;
  payload: {
    order: {
      entity: {
        notes?: { userId?: string; planId?: string };
      };
    };
  };
}

export async function handleWebhookEvent(
  repo: UserRepository,
  body: RazorpayWebhookPayload,
  now: Date = new Date()
): Promise<{ handled: boolean }> {
  if (body.event !== 'payment.captured') {
    return { handled: false };
  }

  const { userId, planId } = body.payload.order.entity.notes ?? {};
  if (!userId || !planId || !(planId in PLANS)) {
    return { handled: false };
  }

  const plan = PLANS[planId as PlanId];
  const expiresAt = new Date(now.getTime() + plan.durationMs);
  await repo.activateSubscription(userId, expiresAt);
  return { handled: true };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/lib/webhookHandler.test.ts`
Expected: all 5 tests pass.

- [ ] **Step 5: Implement the route**

Create `app/api/payment/webhook/route.ts`:
```ts
import { NextRequest, NextResponse } from 'next/server';
import { verifyWebhookSignature, handleWebhookEvent } from '@/lib/webhookHandler';
import { prismaUserRepository } from '@/lib/userRepository';

export async function POST(req: NextRequest) {
  const rawBody = await req.text();
  const signature = req.headers.get('x-razorpay-signature') ?? '';
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET!;

  if (!verifyWebhookSignature(rawBody, signature, secret)) {
    return NextResponse.json({ error: 'Invalid signature.' }, { status: 400 });
  }

  const body = JSON.parse(rawBody);
  await handleWebhookEvent(prismaUserRepository, body);
  return NextResponse.json({ received: true });
}
```

- [ ] **Step 6: Push and verify on CI**

```bash
git add lib/webhookHandler.ts app/api/payment/webhook tests/lib/webhookHandler.test.ts
git commit -m "feat: add Razorpay webhook with signature verification and idempotent activation"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 10: Landing page, Navbar, Footer

**Files:**
- Modify: `app/page.tsx` (replace the `create-next-app` placeholder)
- Create: `components/Navbar.tsx`
- Create: `components/Footer.tsx`
- Test: `tests/app/page.test.tsx`

**Interfaces:**
- Consumes: nothing from earlier tasks (no data fetching — pure marketing content).
- Produces: `Navbar`, `Footer` — reused by every later page task.

- [ ] **Step 1: Install a component-testing dependency**

```bash
npm install -D @testing-library/react @testing-library/jest-dom jsdom
```

Update `vitest.config.ts` to add a jsdom environment for component tests (keep the existing `node` environment as default for `lib`/`app/api` tests, override per-file):
```ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'node',
    environmentMatchGlobs: [['tests/app/**/*.test.tsx', 'jsdom']],
    setupFiles: ['./tests/setup.ts'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
});
```

Create `tests/setup.ts`:
```ts
import '@testing-library/jest-dom/vitest';
```

- [ ] **Step 2: Write the failing test**

Create `tests/app/page.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import Page from '../../app/page';

describe('landing page', () => {
  it('renders a CTA linking to /signup', () => {
    render(<Page />);
    const cta = screen.getByRole('link', { name: /start free trial/i });
    expect(cta).toHaveAttribute('href', '/signup');
  });

  it('answers the required FAQ questions', () => {
    render(<Page />);
    expect(screen.getByText(/no credit card required/i)).toBeInTheDocument();
    expect(screen.getByText(/what happens after.*trial/i)).toBeInTheDocument();
    expect(screen.getByText(/how (do i|to) cancel/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npm test -- tests/app/page.test.tsx`
Expected: FAIL — placeholder page doesn't have this content.

- [ ] **Step 4: Build `Navbar` and `Footer`**

Create `components/Navbar.tsx`:
```tsx
import Link from 'next/link';

export function Navbar() {
  return (
    <nav className="flex items-center justify-between px-6 py-4">
      <Link href="/" className="text-lg font-semibold">
        AffirmAlarm
      </Link>
      <div className="flex gap-4">
        <Link href="/login" className="text-sm">
          Log in
        </Link>
        <Link href="/signup" className="rounded bg-indigo-600 px-4 py-2 text-sm text-white">
          Start Free Trial
        </Link>
      </div>
    </nav>
  );
}
```

Create `components/Footer.tsx`:
```tsx
import Link from 'next/link';

export function Footer() {
  return (
    <footer className="mt-16 border-t px-6 py-8 text-sm text-gray-500">
      <div className="flex flex-wrap gap-4">
        <Link href="/privacy">Privacy Policy</Link>
        <Link href="/terms">Terms</Link>
        <a href="mailto:support@affirmalarm.app">Contact</a>
        <a href="#" aria-label="App Store">
          App Store
        </a>
        <a href="#" aria-label="Play Store">
          Play Store
        </a>
      </div>
    </footer>
  );
}
```

- [ ] **Step 5: Build the landing page**

Replace `app/page.tsx` in full:
```tsx
import Link from 'next/link';
import { Navbar } from '@/components/Navbar';
import { Footer } from '@/components/Footer';

const FEATURES = [
  { title: 'AI-guided affirmations', body: 'Personalized affirmations generated for you, on-device.' },
  { title: 'Wake up with intention', body: 'Your alarm doesn’t stop until you speak your affirmation.' },
  { title: 'Track your streak', body: 'Watch your consistency build day over day.' },
];

const STEPS = ['Sign up for your free trial', 'Download the app', 'Get started in minutes'];

const FAQS = [
  { q: 'Is it free to try?', a: 'Yes — every account gets a 7-day free trial.' },
  { q: 'Is a credit card required?', a: 'No credit card required to start your trial.' },
  {
    q: 'What happens after my trial ends?',
    a: 'You’ll be asked to choose a plan to continue. Nothing is charged automatically.',
  },
  { q: 'How do I cancel?', a: 'Cancel anytime from your account page — you keep access until the period you already paid for ends.' },
];

export default function Page() {
  return (
    <>
      <Navbar />
      <main className="mx-auto max-w-3xl px-6">
        <section className="py-16 text-center">
          <h1 className="text-4xl font-bold">Start your day with intention</h1>
          <p className="mt-4 text-gray-600">
            AffirmAlarm wakes you up with an alarm you can only dismiss by speaking your affirmation.
          </p>
          <Link
            href="/signup"
            className="mt-8 inline-block rounded bg-indigo-600 px-6 py-3 text-white"
          >
            Start Free Trial
          </Link>
        </section>

        <section className="py-12">
          <h2 className="text-2xl font-semibold">Features</h2>
          <div className="mt-6 grid gap-6 sm:grid-cols-3">
            {FEATURES.map((f) => (
              <div key={f.title}>
                <h3 className="font-medium">{f.title}</h3>
                <p className="mt-1 text-sm text-gray-600">{f.body}</p>
              </div>
            ))}
          </div>
        </section>

        <section className="py-12">
          <h2 className="text-2xl font-semibold">How it works</h2>
          <ol className="mt-6 space-y-2">
            {STEPS.map((s, i) => (
              <li key={s}>
                {i + 1}. {s}
              </li>
            ))}
          </ol>
        </section>

        <section className="py-12">
          <h2 className="text-2xl font-semibold">What people are saying</h2>
          <p className="mt-4 text-sm italic text-gray-500">Testimonials coming soon.</p>
        </section>

        <section className="py-12">
          <h2 className="text-2xl font-semibold">FAQ</h2>
          <dl className="mt-6 space-y-4">
            {FAQS.map((f) => (
              <div key={f.q}>
                <dt className="font-medium">{f.q}</dt>
                <dd className="mt-1 text-sm text-gray-600">{f.a}</dd>
              </div>
            ))}
          </dl>
        </section>
      </main>
      <Footer />
    </>
  );
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `npm test -- tests/app/page.test.tsx`
Expected: both tests pass.

- [ ] **Step 7: Push and verify on CI**

```bash
git add components/Navbar.tsx components/Footer.tsx app/page.tsx tests/app/page.test.tsx tests/setup.ts vitest.config.ts package.json package-lock.json
git commit -m "feat: build landing page with Navbar and Footer"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 11: `/signup` and `/login` pages

**Files:**
- Create: `app/signup/page.tsx`
- Create: `app/login/page.tsx`
- Test: `tests/app/signup.test.tsx`
- Test: `tests/app/login.test.tsx`

**Interfaces:**
- Consumes: `POST /api/auth/signup` and `POST /api/auth/login` (Task 6) via client-side `fetch`.
- Produces: on success, redirects to `/download` (signup) or `/account` (login), matching the design spec's flow.

- [ ] **Step 1: Write the failing tests**

Create `tests/app/signup.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import SignupPage from '../../app/signup/page';

describe('signup page', () => {
  it('renders email, password fields, and the no-credit-card note', () => {
    render(<SignupPage />);
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
    expect(screen.getByText(/no credit card required/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /log in/i })).toHaveAttribute('href', '/login');
  });
});
```

Create `tests/app/login.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import LoginPage from '../../app/login/page';

describe('login page', () => {
  it('renders email and password fields plus signup and forgot-password links', () => {
    render(<LoginPage />);
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/password/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /start free trial/i })).toHaveAttribute('href', '/signup');
    expect(screen.getByRole('link', { name: /forgot password/i })).toHaveAttribute('href', '/forgot-password');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/app/signup.test.tsx tests/app/login.test.tsx`
Expected: FAIL — neither page exists.

- [ ] **Step 3: Implement the signup page**

Create `app/signup/page.tsx`:
```tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const res = await fetch('/api/auth/signup', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    if (!res.ok) {
      const body = await res.json();
      setError(body.error ?? 'Something went wrong.');
      setLoading(false);
      return;
    }

    router.push('/download');
  }

  return (
    <main className="mx-auto max-w-sm px-6 py-16">
      <h1 className="text-2xl font-semibold">Start your free trial</h1>
      <p className="mt-1 text-sm text-gray-600">No credit card required.</p>
      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <div>
          <label htmlFor="email" className="block text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        <div>
          <label htmlFor="password" className="block text-sm font-medium">
            Password
          </label>
          <input
            id="password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={loading}
          className="w-full rounded bg-indigo-600 px-4 py-2 text-white disabled:opacity-50"
        >
          {loading ? 'Creating account…' : 'Start Free Trial'}
        </button>
      </form>
      <p className="mt-4 text-sm">
        Already have an account? <Link href="/login">Log in</Link>
      </p>
    </main>
  );
}
```

- [ ] **Step 4: Implement the login page**

Create `app/login/page.tsx`:
```tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    if (!res.ok) {
      const body = await res.json();
      setError(body.error ?? 'Something went wrong.');
      setLoading(false);
      return;
    }

    router.push('/account');
  }

  return (
    <main className="mx-auto max-w-sm px-6 py-16">
      <h1 className="text-2xl font-semibold">Log in</h1>
      <form onSubmit={handleSubmit} className="mt-6 space-y-4">
        <div>
          <label htmlFor="email" className="block text-sm font-medium">
            Email
          </label>
          <input
            id="email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        <div>
          <label htmlFor="password" className="block text-sm font-medium">
            Password
          </label>
          <input
            id="password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="mt-1 w-full rounded border px-3 py-2"
          />
        </div>
        {error && <p className="text-sm text-red-600">{error}</p>}
        <button
          type="submit"
          disabled={loading}
          className="w-full rounded bg-indigo-600 px-4 py-2 text-white disabled:opacity-50"
        >
          {loading ? 'Logging in…' : 'Log in'}
        </button>
      </form>
      <div className="mt-4 flex justify-between text-sm">
        <Link href="/signup">Start free trial</Link>
        <Link href="/forgot-password">Forgot password?</Link>
      </div>
    </main>
  );
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npm test -- tests/app/signup.test.tsx tests/app/login.test.tsx`
Expected: both files pass.

- [ ] **Step 6: Push and verify on CI**

```bash
git add app/signup app/login tests/app/signup.test.tsx tests/app/login.test.tsx
git commit -m "feat: add signup and login pages"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 12: `/download` page

**Files:**
- Create: `app/download/page.tsx`
- Test: `tests/app/download.test.tsx`

**Interfaces:**
- Consumes: `GET /api/subscription-status` (Task 7) server-side, reading the session cookie `withAuth` already accepts.

- [ ] **Step 1: Write the failing test**

Create `tests/app/download.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import DownloadPage from '../../app/download/DownloadPageContent';

describe('download page content', () => {
  it('shows days remaining and both store buttons', () => {
    render(<DownloadPage daysRemaining={7} />);
    expect(screen.getByText(/7 days? remaining/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /app store/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /play store/i })).toBeInTheDocument();
    expect(screen.getByText(/log in with your email/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/app/download.test.tsx`
Expected: FAIL — `app/download/DownloadPageContent.tsx` does not exist.

- [ ] **Step 3: Implement**

Create `app/download/DownloadPageContent.tsx` (presentational, unit-testable without a server round trip):
```tsx
export function DownloadPageContent({ daysRemaining }: { daysRemaining: number }) {
  return (
    <main className="mx-auto max-w-md px-6 py-16 text-center">
      <h1 className="text-2xl font-semibold">You&rsquo;re all set</h1>
      <p className="mt-2 text-gray-600">
        Your trial has started — {daysRemaining} {daysRemaining === 1 ? 'day' : 'days'} remaining.
      </p>
      <div className="mt-8 flex flex-col items-center gap-3">
        <a href="#" className="rounded bg-black px-6 py-3 text-white">
          App Store
        </a>
        <a href="#" className="rounded bg-black px-6 py-3 text-white">
          Play Store
        </a>
      </div>
      <p className="mt-8 text-sm text-gray-600">
        Download the app, open it, then log in with your email to get started.
      </p>
    </main>
  );
}

export default DownloadPageContent;
```

Create `app/download/page.tsx` (server component — fetches real status, passes it to the tested presentational component):
```tsx
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { verifyToken } from '@/lib/auth';
import { prismaUserRepository } from '@/lib/userRepository';
import { daysRemaining } from '@/lib/subscription';
import { DownloadPageContent } from './DownloadPageContent';

export const dynamic = 'force-dynamic';

export default async function DownloadPage() {
  const token = (await cookies()).get('affirmalarm_session')?.value;
  const payload = token ? verifyToken(token) : null;
  if (!payload) redirect('/login');

  const user = await prismaUserRepository.findById(payload.userId);
  if (!user) redirect('/login');

  return <DownloadPageContent daysRemaining={daysRemaining(user.trialEndsAt)} />;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/app/download.test.tsx`
Expected: passes.

- [ ] **Step 5: Push and verify on CI**

```bash
git add app/download tests/app/download.test.tsx
git commit -m "feat: add /download page"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 13: `/account` page with Razorpay checkout

**Files:**
- Create: `components/RazorpayCheckout.tsx`
- Create: `app/account/AccountPageContent.tsx`
- Create: `app/account/page.tsx`
- Test: `tests/app/account.test.tsx`

**Interfaces:**
- Consumes: `POST /api/payment/create-order` (Task 8), `GET /api/subscription-status` (Task 7), `PLANS` (Task 2).

- [ ] **Step 1: Write the failing test**

Create `tests/app/account.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AccountPageContent } from '../../app/account/AccountPageContent';

describe('AccountPageContent', () => {
  it('shows days remaining and plan CTAs while on trial', () => {
    render(<AccountPageContent email="a@b.com" status="trial" daysRemaining={3} subscriptionExpiresAt={null} />);
    expect(screen.getByText(/3 days? remaining/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /monthly/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /annual/i })).toBeInTheDocument();
  });

  it('shows plan name and renewal date, plus a cancel link, when active', () => {
    render(
      <AccountPageContent
        email="a@b.com"
        status="active"
        daysRemaining={0}
        subscriptionExpiresAt={new Date('2026-02-01T00:00:00Z')}
      />
    );
    expect(screen.getByText(/active/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /cancel/i })).toHaveAttribute('href', '/account/cancel');
  });

  it('shows an expired message and prominent plan CTAs when expired', () => {
    render(<AccountPageContent email="a@b.com" status="expired" daysRemaining={0} subscriptionExpiresAt={null} />);
    expect(screen.getByText(/trial has ended/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /monthly/i })).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/app/account.test.tsx`
Expected: FAIL — files don't exist.

- [ ] **Step 3: Implement `RazorpayCheckout`**

Create `components/RazorpayCheckout.tsx`:
```tsx
'use client';

import { useState } from 'react';

declare global {
  interface Window {
    Razorpay: new (options: Record<string, unknown>) => { open: () => void };
  }
}

function loadRazorpayScript(): Promise<boolean> {
  return new Promise((resolve) => {
    if (window.Razorpay) {
      resolve(true);
      return;
    }
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.onload = () => resolve(true);
    script.onerror = () => resolve(false);
    document.body.appendChild(script);
  });
}

interface RazorpayCheckoutProps {
  planId: 'monthly' | 'annual';
  label: string;
  onPaymentSubmitted: () => void;
}

export function RazorpayCheckout({ planId, label, onPaymentSubmitted }: RazorpayCheckoutProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleClick() {
    setLoading(true);
    setError(null);

    const scriptLoaded = await loadRazorpayScript();
    if (!scriptLoaded) {
      setError('Could not load the payment provider. Check your connection and try again.');
      setLoading(false);
      return;
    }

    const orderRes = await fetch('/api/payment/create-order', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ planId }),
    });
    if (!orderRes.ok) {
      setError('Could not start checkout. Please try again.');
      setLoading(false);
      return;
    }
    const order = await orderRes.json();

    const razorpay = new window.Razorpay({
      key: order.key_id,
      amount: order.amount,
      currency: order.currency,
      order_id: order.order_id,
      name: 'AffirmAlarm',
      handler: () => {
        onPaymentSubmitted();
      },
      modal: {
        ondismiss: () => setLoading(false),
      },
    });
    razorpay.open();
    setLoading(false);
  }

  return (
    <div>
      <button
        onClick={handleClick}
        disabled={loading}
        className="rounded bg-indigo-600 px-4 py-2 text-white disabled:opacity-50"
      >
        {loading ? 'Loading…' : label}
      </button>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
    </div>
  );
}
```

- [ ] **Step 4: Implement `AccountPageContent`**

Create `app/account/AccountPageContent.tsx`:
```tsx
'use client';

import { useState } from 'react';
import Link from 'next/link';
import { RazorpayCheckout } from '@/components/RazorpayCheckout';
import { PLANS } from '@/lib/config';

interface AccountPageContentProps {
  email: string;
  status: 'trial' | 'active' | 'expired';
  daysRemaining: number;
  subscriptionExpiresAt: Date | null;
}

async function pollUntilActive(maxAttempts = 10, intervalMs = 1500): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    const res = await fetch('/api/subscription-status');
    if (res.ok) {
      const data = await res.json();
      if (data.status === 'active') return true;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return false;
}

export function AccountPageContent({ email, status, daysRemaining, subscriptionExpiresAt }: AccountPageContentProps) {
  const [processing, setProcessing] = useState(false);
  const [confirmed, setConfirmed] = useState(false);

  async function handlePaymentSubmitted() {
    setProcessing(true);
    const becameActive = await pollUntilActive();
    setProcessing(false);
    if (becameActive) {
      setConfirmed(true);
      window.location.reload();
    }
  }

  const planCtas = (
    <div className="mt-4 flex gap-4">
      {(Object.keys(PLANS) as Array<keyof typeof PLANS>).map((planId) => (
        <RazorpayCheckout
          key={planId}
          planId={planId}
          label={`${PLANS[planId].label} — ₹${PLANS[planId].priceInPaise / 100}`}
          onPaymentSubmitted={handlePaymentSubmitted}
        />
      ))}
    </div>
  );

  return (
    <main className="mx-auto max-w-md px-6 py-16">
      <h1 className="text-2xl font-semibold">Account</h1>
      <p className="mt-1 text-sm text-gray-600">{email}</p>

      {processing && <p className="mt-4 text-sm">Confirming your payment…</p>}
      {confirmed && <p className="mt-4 text-sm text-green-600">Payment confirmed!</p>}

      {status === 'trial' && (
        <div className="mt-6">
          <p>
            {daysRemaining} {daysRemaining === 1 ? 'day' : 'days'} remaining in your trial.
          </p>
          {planCtas}
        </div>
      )}

      {status === 'active' && (
        <div className="mt-6">
          <p className="font-medium text-green-700">Active</p>
          {subscriptionExpiresAt && (
            <p className="text-sm text-gray-600">Renews on {subscriptionExpiresAt.toLocaleDateString()}.</p>
          )}
          <Link href="/account/cancel" className="mt-4 inline-block text-sm text-red-600">
            Cancel subscription
          </Link>
        </div>
      )}

      {status === 'expired' && (
        <div className="mt-6">
          <p className="font-medium text-red-700">Your trial has ended.</p>
          {planCtas}
        </div>
      )}
    </main>
  );
}
```

- [ ] **Step 5: Implement the server page**

Create `app/account/page.tsx`:
```tsx
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { verifyToken } from '@/lib/auth';
import { prismaUserRepository } from '@/lib/userRepository';
import { getSubscriptionStatus, daysRemaining } from '@/lib/subscription';
import { AccountPageContent } from './AccountPageContent';

export const dynamic = 'force-dynamic';

export default async function AccountPage() {
  const token = (await cookies()).get('affirmalarm_session')?.value;
  const payload = token ? verifyToken(token) : null;
  if (!payload) redirect('/login');

  const user = await prismaUserRepository.findById(payload.userId);
  if (!user) redirect('/login');

  const status = getSubscriptionStatus(user);

  return (
    <AccountPageContent
      email={user.email}
      status={status}
      daysRemaining={status === 'trial' ? daysRemaining(user.trialEndsAt) : 0}
      subscriptionExpiresAt={user.subscriptionExpiresAt}
    />
  );
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `npm test -- tests/app/account.test.tsx`
Expected: all 3 tests pass.

- [ ] **Step 7: Push and verify on CI**

```bash
git add components/RazorpayCheckout.tsx app/account tests/app/account.test.tsx
git commit -m "feat: add /account page with Razorpay checkout"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 14: `/account/cancel` page

**Files:**
- Create: `app/api/subscription/cancel/route.ts`
- Create: `app/account/cancel/CancelPageContent.tsx`
- Create: `app/account/cancel/page.tsx`
- Test: `tests/app/cancel.test.tsx`

**Interfaces:**
- Consumes: `withAuth` (Task 5), `UserRepository` (Task 5) — this task adds one new repository method, `scheduleCancel`, since none of the earlier tasks needed "stop renewing but keep access until expiry" semantics. Also modifies `app/account/AccountPageContent.tsx`, `app/account/page.tsx`, and `tests/app/account.test.tsx` (all from Task 13) to surface the resulting `cancelAtPeriodEnd` flag — without this, the flag would be written but never read anywhere, i.e. dead state.

- [ ] **Step 1: Add a `cancelAtPeriodEnd` field and `scheduleCancel` repository method**

`getSubscriptionStatus` (Task 4) returns `'active'` only when `subscriptionStatus === 'active' AND subscriptionExpiresAt > now`. Cancellation must **not** touch `subscriptionStatus` or `subscriptionExpiresAt` — doing so would revoke access immediately instead of "at period end." Add a separate informational flag instead.

Modify `prisma/schema.prisma`, add one field to `User`:
```prisma
  cancelAtPeriodEnd     Boolean             @default(false)
```

Run:
```bash
npx prisma migrate dev --name add_cancel_at_period_end --create-only
```

Modify `lib/userRepository.ts` — add to the `UserRepository` interface:
```ts
  scheduleCancel(id: string): Promise<User>;
```
And to `prismaUserRepository`:
```ts
  scheduleCancel: (id) =>
    prisma.user.update({
      where: { id },
      data: { cancelAtPeriodEnd: true },
    }),
```

This flag is purely informational — access is governed entirely by `subscriptionExpiresAt`, unchanged by cancellation, exactly as the spec requires ("user retains access until expiry date"). There is no auto-renewal logic anywhere in this plan to disable (Razorpay orders here are one-off purchases, not Razorpay Subscriptions), so `cancelAtPeriodEnd` exists only so `/account` can show "canceled, access until `<date>`" instead of "active" — Step 6 below wires that display in.

- [ ] **Step 2: Write the failing test**

Create `tests/app/cancel.test.tsx`:
```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CancelPageContent } from '../../app/account/cancel/CancelPageContent';

describe('CancelPageContent', () => {
  it('confirms cancellation and calls the cancel API on confirm', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ ok: true }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    render(<CancelPageContent subscriptionExpiresAt={new Date('2026-02-01T00:00:00Z')} />);
    expect(screen.getByText(/keep your access until/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /confirm cancellation/i }));

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith('/api/subscription/cancel', expect.objectContaining({ method: 'POST' }));
    });

    vi.unstubAllGlobals();
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npm test -- tests/app/cancel.test.tsx`
Expected: FAIL — files don't exist.

- [ ] **Step 4: Implement the cancel API route**

Create `app/api/subscription/cancel/route.ts`:
```ts
import { NextResponse } from 'next/server';
import { withAuth } from '@/lib/withAuth';
import { prismaUserRepository } from '@/lib/userRepository';

export const POST = withAuth(async (_req, user) => {
  await prismaUserRepository.scheduleCancel(user.id);
  return NextResponse.json({ ok: true });
});
```

- [ ] **Step 5: Implement `CancelPageContent` and the server page**

Create `app/account/cancel/CancelPageContent.tsx`:
```tsx
'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

export function CancelPageContent({ subscriptionExpiresAt }: { subscriptionExpiresAt: Date | null }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);

  async function handleConfirm() {
    setConfirming(true);
    await fetch('/api/subscription/cancel', { method: 'POST' });
    router.push('/account');
  }

  return (
    <main className="mx-auto max-w-md px-6 py-16">
      <h1 className="text-2xl font-semibold">Cancel subscription</h1>
      <p className="mt-4 text-sm text-gray-600">
        {subscriptionExpiresAt
          ? `You'll keep your access until ${subscriptionExpiresAt.toLocaleDateString()}. You won't be charged again after that.`
          : "You'll keep your access until your current period ends."}
      </p>
      <button
        onClick={handleConfirm}
        disabled={confirming}
        className="mt-6 rounded bg-red-600 px-4 py-2 text-white disabled:opacity-50"
      >
        {confirming ? 'Canceling…' : 'Confirm cancellation'}
      </button>
    </main>
  );
}
```

Create `app/account/cancel/page.tsx`:
```tsx
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { verifyToken } from '@/lib/auth';
import { prismaUserRepository } from '@/lib/userRepository';
import { CancelPageContent } from './CancelPageContent';

export const dynamic = 'force-dynamic';

export default async function CancelPage() {
  const token = (await cookies()).get('affirmalarm_session')?.value;
  const payload = token ? verifyToken(token) : null;
  if (!payload) redirect('/login');

  const user = await prismaUserRepository.findById(payload.userId);
  if (!user) redirect('/login');

  return <CancelPageContent subscriptionExpiresAt={user.subscriptionExpiresAt} />;
}
```

- [ ] **Step 6: Surface `cancelAtPeriodEnd` on `/account`**

Modify `app/account/AccountPageContent.tsx` — add `cancelAtPeriodEnd: boolean` to `AccountPageContentProps`, and replace the `status === 'active'` branch:
```tsx
      {status === 'active' && (
        <div className="mt-6">
          {cancelAtPeriodEnd ? (
            <p className="font-medium text-amber-700">Canceled</p>
          ) : (
            <p className="font-medium text-green-700">Active</p>
          )}
          {subscriptionExpiresAt && (
            <p className="text-sm text-gray-600">
              {cancelAtPeriodEnd
                ? `You'll keep access until ${subscriptionExpiresAt.toLocaleDateString()}.`
                : `Renews on ${subscriptionExpiresAt.toLocaleDateString()}.`}
            </p>
          )}
          {!cancelAtPeriodEnd && (
            <Link href="/account/cancel" className="mt-4 inline-block text-sm text-red-600">
              Cancel subscription
            </Link>
          )}
        </div>
      )}
```

Modify `app/account/page.tsx` to pass the new prop:
```tsx
    <AccountPageContent
      email={user.email}
      status={status}
      daysRemaining={status === 'trial' ? daysRemaining(user.trialEndsAt) : 0}
      subscriptionExpiresAt={user.subscriptionExpiresAt}
      cancelAtPeriodEnd={user.cancelAtPeriodEnd}
    />
```

Modify `tests/app/account.test.tsx` (Task 13): add `cancelAtPeriodEnd={false}` to the two existing render calls (they'd otherwise be missing a required prop), and add one new test:
```tsx
  it('shows Canceled instead of Active, and hides the cancel link, once cancelAtPeriodEnd is set', () => {
    render(
      <AccountPageContent
        email="a@b.com"
        status="active"
        daysRemaining={0}
        subscriptionExpiresAt={new Date('2026-02-01T00:00:00Z')}
        cancelAtPeriodEnd={true}
      />
    );
    expect(screen.getByText(/canceled/i)).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /cancel subscription/i })).not.toBeInTheDocument();
  });
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `npm test -- tests/app/account.test.tsx tests/app/cancel.test.tsx`
Expected: all 4 `account.test.tsx` tests and the `cancel.test.tsx` test pass.

- [ ] **Step 8: Push and verify on CI**

```bash
git add prisma lib/userRepository.ts app/api/subscription/cancel app/account/cancel app/account/AccountPageContent.tsx app/account/page.tsx tests/app/cancel.test.tsx tests/app/account.test.tsx
git commit -m "feat: add /account/cancel page, cancellation API, and surface cancelAtPeriodEnd on /account"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 15: `/privacy`, `/terms`, `/forgot-password` static pages

**Files:**
- Create: `app/privacy/page.tsx`
- Create: `app/terms/page.tsx`
- Create: `app/forgot-password/page.tsx`
- Test: `tests/app/staticPages.test.tsx`

**Interfaces:**
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

Create `tests/app/staticPages.test.tsx`:
```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import PrivacyPage from '../../app/privacy/page';
import TermsPage from '../../app/terms/page';
import ForgotPasswordPage from '../../app/forgot-password/page';

describe('static pages', () => {
  it('renders the privacy page', () => {
    render(<PrivacyPage />);
    expect(screen.getByRole('heading', { name: /privacy policy/i })).toBeInTheDocument();
  });

  it('renders the terms page', () => {
    render(<TermsPage />);
    expect(screen.getByRole('heading', { name: /terms/i })).toBeInTheDocument();
  });

  it('renders the forgot-password stub explaining it is not yet available', () => {
    render(<ForgotPasswordPage />);
    expect(screen.getByText(/not (yet )?available/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test -- tests/app/staticPages.test.tsx`
Expected: FAIL — none of the three pages exist.

- [ ] **Step 3: Implement**

Create `app/privacy/page.tsx`:
```tsx
export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="text-2xl font-semibold">Privacy Policy</h1>
      <p className="mt-4 text-sm text-gray-600">
        This is placeholder privacy policy content. Replace with your actual policy before launch.
      </p>
    </main>
  );
}
```

Create `app/terms/page.tsx`:
```tsx
export default function TermsPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="text-2xl font-semibold">Terms of Service</h1>
      <p className="mt-4 text-sm text-gray-600">
        This is placeholder terms content. Replace with your actual terms before launch.
      </p>
    </main>
  );
}
```

Create `app/forgot-password/page.tsx`:
```tsx
import Link from 'next/link';

export default function ForgotPasswordPage() {
  return (
    <main className="mx-auto max-w-md px-6 py-16 text-center">
      <h1 className="text-2xl font-semibold">Password reset</h1>
      <p className="mt-4 text-sm text-gray-600">
        Password reset isn&rsquo;t available yet. Contact support to regain access to your account.
      </p>
      <Link href="/login" className="mt-6 inline-block text-sm text-indigo-600">
        Back to log in
      </Link>
    </main>
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm test -- tests/app/staticPages.test.tsx`
Expected: all 3 pass.

- [ ] **Step 5: Push and verify on CI**

```bash
git add app/privacy app/terms app/forgot-password tests/app/staticPages.test.tsx
git commit -m "feat: add privacy, terms, and forgot-password pages"
git push
export GIT_CONFIG_NOSYSTEM=1
gh run watch
```

---

### Task 16: Final integration, whole-suite verification, deployment README

**Files:**
- Create: `README.md`
- Modify: none (verification-only otherwise)

**Interfaces:**
- Consumes: everything from Tasks 1-15.

- [ ] **Step 1: Full local verification**

```bash
npm run lint
npm run build
npx prisma generate
npm test
```
Expected: all pass. (`npm run build` still doesn't need a live `DATABASE_URL` — every page touching the DB is `force-dynamic`.)

- [ ] **Step 2: Write the deployment README**

Create `README.md`:
```markdown
# AffirmAlarm Web

Backend + website for AffirmAlarm's 7-day trial and subscription billing.
See `docs/` in the `AffirmAlarm` repo for the full design spec.

## Local development

\`\`\`bash
npm install
cp .env.example .env.local   # fill in values below
npx prisma generate
npm run dev
\`\`\`

This sandbox/dev machine has no local Postgres and no running Docker daemon —
`npm run dev` will fail on any DB-touching route without a real `DATABASE_URL`.
Point `DATABASE_URL` at a real Postgres instance (e.g. a free Neon branch) to
develop against a live database locally.

## Required accounts before this can go live

None of these can be provisioned by an agent — they require a human with
billing/ownership access:

1. **Neon** (https://neon.tech) — create a Postgres project, copy the
   connection string into `DATABASE_URL`.
2. **Vercel** (https://vercel.com) — import this GitHub repo, set the env
   vars below in the project settings, deploy.
3. **Razorpay** (https://razorpay.com) — create a merchant account (KYC
   required for live payments), generate API keys (`RAZORPAY_KEY_ID`,
   `RAZORPAY_KEY_SECRET`), and register a webhook pointed at
   `https://<your-domain>/api/payment/webhook` subscribed to the
   `payment.captured` event, copying the resulting secret into
   `RAZORPAY_WEBHOOK_SECRET`.

## Environment variables

| Variable | Description |
|---|---|
| `DATABASE_URL` | Postgres connection string (Neon) |
| `JWT_SECRET` | Long random string, session signing key |
| `RAZORPAY_KEY_ID` | Razorpay API key ID |
| `RAZORPAY_KEY_SECRET` | Razorpay API key secret |
| `RAZORPAY_WEBHOOK_SECRET` | Razorpay webhook signing secret |

## Running migrations against a real database

\`\`\`bash
npx prisma migrate deploy
\`\`\`

## What's intentionally out of scope here

- Real email-based password reset (`/forgot-password` is a stub)
- The mobile app's own login/status-check/paywall UI — that's a separate
  plan (Sub-project B) in the `AffirmAlarm` repo, and depends on this
  project being deployed first so it has a real API to call.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add deployment README"
git push
```

- [ ] **Step 4: Dispatch the final whole-branch review**

Per `superpowers:subagent-driven-development`, dispatch the final review on the most capable available model, covering the full range from Task 1's initial commit through this task's final commit. Pay particular attention to:
- Whether any route ever trusts client-supplied payment/subscription state instead of the webhook (re-check `create-order` and the `/account` polling flow)
- Whether `withAuth`'s cookie-vs-header precedence could let an expired user's stale cookie bypass a header-based mobile check, or vice versa
- Whether Task 14's `cancelAtPeriodEnd` wiring on `/account` is complete and consistent (it should show "Canceled" + no cancel link once set, otherwise "Active" as before) — confirm no other read site was missed
- Whether `.env.example` and the README together give a genuinely deployable picture, or whether anything necessary was missed

This mirrors the AffirmAlarm iOS phases' final review, which caught real cross-cutting gaps despite every task-level review passing — do not skip it.
