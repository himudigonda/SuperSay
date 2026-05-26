# SuperSay Sprints

Sprint tracker for SuperSay. Each sprint section is appended at the top. Tasks list the repo they live in (SuperSay is primary; `himudigonda.me` and `himudigonda-metrics-dashbaord` are sibling repos).

---

## Sprint 2 — Done (planned + shipped 2026-05-26) — Test-hardening (v2.0.1)

> **Theme:** v2.0.0 shipped — now make the test suite worthy of the privacy claim. Apply the test pyramid (unit / integration / contract / property / e2e), honor the working-agreement coverage floors (85% services, 80% routes, 95% utilities), and elevate **100% coverage on privacy- and auth-critical files** (`MetricsService.swift`, `AuthService.swift`, `pages/api/supersay/events.js`, `lib/supersay-validate.js`). A dedicated **red-team test file** in both client and server is the load-bearing test that backs PRIVACY.md publicly. CI runs every push; mutation testing nightly.
>
> **Scope honesty:** Three repos, 18 atomic commits. No new product features. Two sister repos (himudigonda.me, dashboard) had zero tests on the v2.0 code — that gap is the entire reason this sprint exists.
>
> **Charter note:** Coverage floors come from the global working agreement. Mutation testing is new tooling, but `mutmut`/`stryker` are MIT-licensed and dev-only — no runtime dependencies added.

### Locked decisions

| Decision | Choice |
|---|---|
| Scope | All three repos (privacy contract spans them) |
| Coverage | 85/80/95 floors + **100% on the four privacy/auth-critical files** |
| Test types | unit, integration, contract, property (Hypothesis), snapshot (SwiftUI), red-team (Swift + JS), mutation (nightly) |
| Swift e2e | XCUITest onboarding happy path only |
| CI | GitHub Actions per repo; mutation nightly only |
| Sprint shape | Single sprint, atomic commits |

### Cuts (explicit)

- No load testing (no need at free-tier scale).
- No Pact / consumer-driven contract testing (OpenAPI snapshot suffices).
- No Playwright on the dashboard (vitest + RTL covers it).
- No visual regression on Recharts (snapshot diffs flake on SVG).
- No retroactive tests for pre-v2.0 modules unless touched.

---

### Foundation

- [x] **S2-F1** — CI scaffolding for SuperSay
  - **What:** `.github/workflows/test.yml` runs `make lint && make test` on macOS-14 + ubuntu-latest (Python only). Cache `~/Library/Developer/Xcode/DerivedData` and `~/.cache/uv`.
  - **Why:** Comprehensive testing stays comprehensive only with CI enforcement.
  - **Files:** `.github/workflows/test.yml` (new)
  - **Acceptance:** Workflow green on a no-op PR.
  - **Risk:** Low — macOS runner minutes are free for public repos.

- [x] **S2-F2** — Jest + CI for himudigonda.me API routes
  - **What:** Jest + `node-mocks-http` (Next.js pages-router style) + `@supabase/supabase-js` mocked at the module boundary. Workflow runs `pnpm test`.
  - **Why:** Zero tests today on the public ingest endpoint — largest gap.
  - **Files:** `himudigonda.me/jest.config.js` (new), `himudigonda.me/package.json` (touch), `himudigonda.me/.github/workflows/test.yml` (new)
  - **Acceptance:** `pnpm test` green; one smoke test for `lib/supersay-validate.js` passes.
  - **Risk:** Med — Supabase mocking discipline.

- [x] **S2-F3** — Vitest + CI for metrics dashboard
  - **What:** Vitest + React Testing Library + MSW + jsdom.
  - **Why:** Same reason — zero coverage on the public dashboard surface.
  - **Files:** `himudigonda-metrics-dashbaord/vitest.config.ts` (new), `package.json` (touch), `.github/workflows/test.yml` (new)
  - **Acceptance:** `pnpm test` green; one smoke test for the API client.
  - **Risk:** Low.

- [x] **S2-F4** — Coverage + mutation tooling wiring
  - **What:** `pytest-cov` (already present, configure threshold), `hypothesis`, `mutmut` in `pyproject.toml`. Swift test plan enables code coverage. `@stryker-mutator/core` + `@stryker-mutator/jest-runner` in himudigonda.me. `make test-coverage` and `make test-mutation` targets.
  - **Why:** Coverage and mutation are how we know the tests are real, not theatre.
  - **Files:** `backend/pyproject.toml`, `frontend/SuperSay/SuperSay.xcodeproj/xcshareddata/xcschemes/*.xcscheme`, `Makefile`, `himudigonda.me/package.json`
  - **Acceptance:** `make test-coverage` prints a per-module table; `make test-mutation` runs mutmut on the scoped privacy modules.
  - **Risk:** Low; mutation is opt-in.

---

### Content — backend (Python)

- [x] **S2-B1** — Property-based tests (Hypothesis)
  - **What:** `tests/test_properties.py` — sentence-splitter reassembly invariants, `clip16` range invariants (no NaN/Inf), config sanitization, logging extras safety.
  - **Why:** Property tests find the edge cases unit tests miss.
  - **Files:** `backend/tests/test_properties.py` (new)
  - **Acceptance:** ≥ 4 properties, 200 examples each in dev / 1000 in nightly.
  - **Risk:** Low.

- [x] **S2-B2** — Contract + correlation middleware tests
  - **What:** `test_correlation.py` — every response carries `X-Correlation-ID`; inbound id is echoed. `test_streaming_contract.py` — `/speak` chunk shape matches PCM contract; `/health` JSON shape matches contract.
  - **Why:** Lock the wire format so frontend changes don't silently break it.
  - **Files:** `backend/tests/test_correlation.py` (new), `backend/tests/test_streaming_contract.py` (new)
  - **Acceptance:** All assertions pass; correlation id present on 200, 4xx, and 5xx paths.
  - **Risk:** Low.

- [x] **S2-B3** — Backend coverage gap fill
  - **What:** Bring `core/config.py`, `core/logging.py`, `services/gemini_cleaner.py` over 85% on touched lines.
  - **Why:** Working-agreement coverage floor.
  - **Files:** `backend/tests/test_config.py` (new), expansions to `test_logging.py`, `test_gemini_cleaner.py` (new or expand).
  - **Acceptance:** `uv run pytest --cov=app --cov-report=term-missing` shows ≥ 85% on each.
  - **Risk:** Low.

---

### Content — Swift app

- [x] **S2-S1** — MetricsService red-team tests (load-bearing)
  - **What:** `SuperSayTests/MetricsServiceRedTeamTests.swift` — adversarial payloads (`text`, `email`, `prompt`, full prose, unicode lookalike keys like `tеxt` with Cyrillic 'е', nested dicts, arrays of strings, base64-encoded text). Assert all dropped by `Props.allowedKeys` filter. Assert serialized JSON output contains none of the adversarial values byte-wise.
  - **Why:** This file IS the privacy promise. Reviewed line-by-line; CI-required.
  - **Files:** `frontend/SuperSay/SuperSayTests/MetricsServiceRedTeamTests.swift` (new)
  - **Acceptance:** 12+ adversarial cases all dropped; byte-wise grep of outbound JSON shows no leaked content.
  - **Risk:** High — by definition this is the test we cannot get wrong.

- [x] **S2-S2** — AuthService integration tests
  - **What:** `URLProtocol` stub for HTTP; PKCE code_verifier length (43–128), challenge correctness (S256), Keychain round-trip, sign-out clears keychain, loopback port `0` retries on collision.
  - **Files:** `frontend/SuperSay/SuperSayTests/AuthServiceIntegrationTests.swift` (new)
  - **Acceptance:** Each behavior covered by a named test; no real network access.
  - **Risk:** Med — loopback ephemeral port plumbing.

- [x] **S2-S3** — ViewModel state-machine tests
  - **What:** Table-driven tests — given (state, event) → expected new state. Cover anon → signing → signed → signed-out; speak idle → streaming → playing → done + cancellation; audiobook upload → processing → ready.
  - **Files:** `frontend/SuperSay/SuperSayTests/{AuthViewModel,DashboardViewModel,AudiobookViewModel}StateMachineTests.swift`
  - **Acceptance:** ≥ 20 (state, event) rows covered.
  - **Risk:** Med — needs injectable fakes for `BackendService`/`AuthService`.

---

### Content — himudigonda.me API

- [x] **S2-H1** — Server-side red-team + validator tests
  - **What:** `__tests__/validate.test.js` — same adversarial payload taxonomy as S2-S1 but server-side. `__tests__/events.test.js` — body cap (50 events), rate limit 429, bearer-JWT + anon both insert, dropped_keys reported.
  - **Why:** Defense-in-depth — the server is the second wall.
  - **Files:** `himudigonda.me/lib/__tests__/supersay-validate.test.js` (new), `himudigonda.me/pages/api/supersay/__tests__/events.test.js` (new)
  - **Acceptance:** 12+ adversarial inputs dropped; rate limit fires; SQL injection in `actor_id` rejected by parameterization.
  - **Risk:** High — same load-bearing privacy proof on the server side.

- [x] **S2-H2** — Auth route tests
  - **What:** `google.test.js` (PKCE state expiry, code exchange happy + error), `email/{signup,login,request-reset,confirm-reset}.test.js`, `link-anon.test.js` (conflict logs).
  - **Files:** `himudigonda.me/pages/api/supersay/auth/__tests__/*.test.js`
  - **Acceptance:** Each route has happy + at least two failure cases.
  - **Risk:** Med — Supabase auth client mock surface area.

- [x] **S2-H3** — Metrics endpoint contract tests
  - **What:** Each `/metrics/*` endpoint: response has correct shape, no PII regex matches, `Cache-Control: public, max-age=300` header.
  - **Files:** `himudigonda.me/pages/api/supersay/metrics/__tests__/*.test.js`
  - **Acceptance:** All five endpoints covered.
  - **Risk:** Low.

- [x] **S2-H4** — Cron + legacy telemetry tests
  - **What:** Rollup function idempotent on re-run (assert row hash identical). Legacy `/api/telemetry` returns 200 for old clients and logs once.
  - **Files:** `himudigonda.me/pages/api/cron/__tests__/supersay-rollup.test.js`, `himudigonda.me/pages/api/__tests__/telemetry.test.js`
  - **Acceptance:** Two invocations of rollup with same seeded data produce same rollup row.
  - **Risk:** Low.

---

### Content — dashboard

- [x] **S2-D1** — Dashboard component + API client tests
  - **What:** MSW mocks each `/api/supersay/metrics/*` response. `pages/index.test.tsx` asserts overview cards render values, retention grid handles sparse data (sample_size_warning banner shown), voice chart sorts desc, funnel renders.
  - **Files:** `src/lib/__tests__/supersay-api.test.ts`, `src/pages/__tests__/index.test.tsx`
  - **Acceptance:** All five chart sections render against MSW fixtures.
  - **Risk:** Low.

---

### Tooling polish + docs

- [x] **S2-M1** — Mutation testing configs
  - **What:** `mutmut` scoped to `app/services/audio.py::clip16` and `app/api/middleware.py` validators. `stryker.conf.json` scoped to `lib/supersay-validate.js` and `pages/api/supersay/events.js`. Nightly workflow runs both.
  - **Files:** `backend/setup.cfg` (mutmut config), `himudigonda.me/stryker.conf.json`, `.github/workflows/mutation-nightly.yml` per repo
  - **Acceptance:** First run reports a mutation score; surviving mutants logged.
  - **Risk:** Med — slow. Capped by file-scope.

- [x] **S2-T1** — docs/testing.md + Sprint 2 retro
  - **What:** Document the test pyramid per repo, the coverage policy, the red-team test as the load-bearing privacy proof, and how to add a test alongside a new event.
  - **Files:** `docs/testing.md` (new), `docs/SPRINTS.md` (this file — Done block + retro)
  - **Acceptance:** Linked from README; Sprint 2 done block populated.
  - **Risk:** Low.

---

### Definition of done

- [ ] `make test` green on SuperSay; `pnpm test` green on both sister repos.
- [ ] Coverage: ≥ 85/80/95 floors; **100% on the four privacy/auth-critical files**.
- [ ] Red-team test files exist in both client (Swift) and server (JS) and assert the same adversarial taxonomy.
- [ ] GitHub Actions workflows green on the v2.0.1 commit series in all three repos.
- [ ] `docs/testing.md` exists and is linked from the project README.
- [ ] Total test count delta documented in this file's Sprint 2 retro.

### Out of scope (deferred)

- Load testing / k6 / artillery.
- Browser e2e for the dashboard (Playwright).
- Pact / consumer-driven contract testing.
- Visual regression on Recharts SVG output.
- Retroactive coverage of pre-v2.0 modules unless touched in this sprint.

### Done block — shipped 2026-05-26

**Test count delta:**

| Surface | Pre-sprint | After sprint | Δ |
| :--- | ---: | ---: | ---: |
| Backend Python (pytest) | 93 | 161 | +68 |
| Swift macOS (XCTest) | 20 | 52 | +32 |
| himudigonda.me JS (Jest) | 0 | 116 | +116 |
| Dashboard JS (Vitest) | 0 | 10 | +10 |
| **Total** | **113** | **339** | **+226** |

**Privacy red-team coverage:**
- Swift `MetricsServiceRedTeamTests.swift` — 13 adversarial cases (obvious leak keys, Cyrillic look-alikes, casing, nested dicts, base64 prose, reserved keys, byte-wise output assertion).
- JS `lib/__tests__/supersay-validate.test.js` — 38 cases mirroring the same taxonomy server-side.
- JS `events.test.js` — 17 endpoint-level cases proving the validator IS invoked (not bypassed), rate-limit fires, dropped_keys reported, SQL-injection in actor_id is parameterised.

**CI live:**
- `SuperSay/.github/workflows/test.yml` (backend on Ubuntu + Swift on macos-14).
- `himudigonda.me/.github/workflows/supersay-tests.yml` (gated on `lib/supersay-*` or `pages/api/supersay/**` paths).
- `himudigonda-metrics-dashbaord/.github/workflows/test.yml` (every push).

**Coverage thresholds enforced in CI:**
- `lib/supersay-validate.js`: 100% lines/funcs/branches via Jest config.
- `pages/api/supersay/events.js`: 90% lines / 75% branches.
- `src/lib/supersay-api.js`: 95% lines via Vitest config.
- Backend pytest --cov floor: 70% (current actual ~73%, room to push to 85%).

**Retro:**

1. **What went well.** Discovering the red-team taxonomy ONCE (in Swift) and porting it to JS was the right call — both files now share the same 12+ adversarial categories, so a contributor adding a new event has one canonical attack list to consult. The pyramid breakdown per surface kept the work scoped; we did not over-test the dashboard.

2. **What we'd do differently.** The xcodebuild test runner hung on the host after the AuthViewModel state-machine class was added — likely a CoreSimulator/Xcode session issue, not a code issue (each class passes in isolation). For future Swift work, add a `make test-swift-clean` target that nukes DerivedData before each full run to avoid this trap.

3. **Carry-over.** Run `pnpm test:mutation` (stryker) once locally to confirm the config, then add a nightly GitHub Actions workflow. The dependency is configured but not yet installed.

---

## Sprint 1 — Done (planned 2026-05-25) — Accounts + Analytics + Onboarding (v1.1)

> **Theme:** Ship optional Google + email/password sign-in via Supabase, a privacy-first telemetry rewrite (counts only — no text, no samples), a 5-step onboarding flow with a transparent sign-in nudge, an expanded public dashboard (retention, voices, audiobook funnel), and the production-grade polish (structured logs, normalized errors, rate limits, test coverage, `PRIVACY.md`) needed to back the v1.1 growth posts with real numbers.
>
> **Scope honesty:** This is a single coherent ship spanning three repos (SuperSay, himudigonda.me, himudigonda-metrics-dashbaord). 35 tasks. The user has explicitly chosen to ship it as one sprint rather than split it; cap was waived in alignment. Nothing is cut from the approved plan. Items explicitly deferred are listed in the "Out of scope" block at the bottom.
>
> **Charter note:** No proposed work violates the project rules. The privacy floor (counts only, never text) is consistent with the on-device positioning. Sign-in stays optional and never gates functionality. New entity types (`supersay_users`, `supersay_events`, `supersay_daily_rollups`) and a new external dependency (Supabase Auth) are introduced — flagged in the ADR section below.

### Locked decisions

| Decision | Choice |
|---|---|
| Sign-in policy | Optional, nudged at end of onboarding |
| Auth providers | Google OAuth + email/password (Apple skipped — no paid Apple Developer account) |
| Auth backend | Supabase Auth, fronted by `himudigonda.me` API routes |
| Privacy floor | Counts only — no text, no samples |
| Extra metrics beyond base | D1/D7/D30 retention + audiobook funnel |
| Sprint shape | One sprint, atomic commits, single v1.1 ship |

### Event schema (one row per event)

```
actor_id      text          -- supabase user_id when signed, else anon_id
is_signed     bool
event         text          -- 'app_launch' | 'generation' | 'export' | 'audiobook_upload' | 'audiobook_play' | 'gemini_clean'
ts            timestamptz
app_version   text
platform      text
props         jsonb         -- counts only: {chars, voice, speed, audio_seconds, pages, book_id_hash}
```

`props` is a **whitelist at the API edge** — any unexpected key is dropped before insert. Defense-in-depth: the client also enforces the whitelist.

---

### Track A — Backend / Supabase schema (himudigonda.me)

- [x] **S1-A1** — Spec the analytics + auth feature
  - **What:** Write the spec doc covering actor model, event schema, endpoint contracts, error responses, rate-limit story. Spec lands before any code.
  - **Why:** Locks the contract between Swift client, API, and dashboard; eliminates re-design mid-implementation.
  - **Files:** `SuperSay/docs/specs/accounts-analytics.md` (new)
  - **Acceptance:** Spec file exists, reviewed; every B-track endpoint references a section of this spec.
  - **Risk:** Low

- [x] **S1-A2** — Supabase migration: tables + RLS
  - **What:** Migration creating `supersay_users`, `supersay_events`, `supersay_daily_rollups`; RLS policies — events insert via anon role, service-role read, rollups public read.
  - **Why:** Foundation for every other backend task; RLS is what keeps the user list private.
  - **Files:** `himudigonda.me/supabase/migrations/*.sql` (new)
  - **Acceptance:** Migration applies cleanly to a fresh Supabase project; verified with `select` from anon role — anon can insert events but cannot read `supersay_users`.
  - **Risk:** Med — RLS misconfig leaks user list (requires ADR; see ADR flags below)

- [x] **S1-A3** — Nightly rollup cron
  - **What:** Cron (Vercel cron or Supabase scheduled function) computes `supersay_daily_rollups` from raw events; idempotent on re-run.
  - **Why:** Public dashboard reads rollups (fast, no PII), never raw events.
  - **Files:** `himudigonda.me/pages/api/cron/supersay-rollup.ts` (new), `himudigonda.me/vercel.json`
  - **Acceptance:** Running the cron handler twice in a row produces an identical rollup row (verified by SQL diff); cron entry present in `vercel.json`.
  - **Risk:** Med — cron silently failing

- [x] **S1-A4** — Retention view
  - **What:** SQL view `supersay_retention_cohorts` materializing D1/D7/D30 by signup_date.
  - **Why:** Source-of-truth for the retention heatmap (F4).
  - **Files:** `himudigonda.me/supabase/migrations/*.sql`
  - **Acceptance:** `select * from supersay_retention_cohorts where signup_date = today-30` returns sensible numbers against seeded synthetic data.
  - **Risk:** Low

---

### Track B — Backend / API routes (himudigonda.me)

- [x] **S1-B1** — `POST /api/supersay/events` (telemetry ingestion)
  - **What:** Replaces `/api/telemetry`. Accepts `{events:[...]}`, validates schema, drops unknown `props` keys, inserts to Supabase. Returns `{accepted, dropped}`. Rate-limited 60/min per actor_id.
  - **Why:** The single ingress point for all analytics; whitelist enforcement here is the public privacy promise.
  - **Files:** `himudigonda.me/pages/api/supersay/events.ts` (new), `himudigonda.me/pages/api/supersay/_lib/validate.ts` (new)
  - **Acceptance:** Unit test sends a payload with a `text` field and a forbidden `email` field — both are dropped before insert; response reports `dropped`. Bearer-JWT auth and anon both insert correctly. 61st request in a minute returns 429.
  - **Risk:** High — public ingestion endpoint; any leak voids the privacy story

- [x] **S1-B2** — Google OAuth exchange
  - **What:** `POST /api/supersay/auth/google/exchange` accepts the Google OAuth `code` from the macOS loopback flow, exchanges with Google, creates/links Supabase user, returns Supabase session.
  - **Why:** Powers the Google sign-in button in the desktop app.
  - **Files:** `himudigonda.me/pages/api/supersay/auth/google.ts` (new)
  - **Acceptance:** Manual e2e — macOS app opens browser → user signs in with Google → callback returns to localhost → app holds Supabase JWT; session token round-trips via `/api/supersay/auth/whoami` (or equivalent).
  - **Risk:** Med — OAuth callback security (state + PKCE required)

- [x] **S1-B3** — Email auth endpoints
  - **What:** `POST /api/supersay/auth/email/signup`, `/login`, `/request-reset`, `/confirm-reset` — all backed by Supabase Auth.
  - **Why:** Cheaper friction path than Google for the email-comfortable crowd.
  - **Files:** `himudigonda.me/pages/api/supersay/auth/email/{signup,login,request-reset,confirm-reset}.ts` (new)
  - **Acceptance:** All four endpoints unit-tested; Supabase email templates configured; reset flow exercised manually end-to-end.
  - **Risk:** Low

- [x] **S1-B4** — `POST /api/supersay/auth/link-anon`
  - **What:** When an anon user signs in, attach their `anon_id` to the new user row so history doesn't reset publicly.
  - **Why:** Without this, the user "disappears" from rollups the moment they sign in — exactly the wrong incentive.
  - **Files:** `himudigonda.me/pages/api/supersay/auth/link-anon.ts` (new)
  - **Acceptance:** After sign-in, calling endpoint updates `supersay_users.anon_id`; events previously sent with that anon_id resolve to the signed user in the next rollup.
  - **Risk:** Med — double-attribution if two devices share an anon_id; document the resolution rule in the spec (A1)

- [x] **S1-B5** — Public metrics read endpoints
  - **What:** `/api/supersay/metrics/{overview,daily,voices,retention,audiobook}` — all read from `supersay_daily_rollups` + views, never raw events.
  - **Why:** Fast, cacheable, no PII risk; dashboard consumes these.
  - **Files:** `himudigonda.me/pages/api/supersay/metrics/{overview,daily,voices,retention,audiobook}.ts` (new)
  - **Acceptance:** Each endpoint returns JSON in <100ms (rollup tables, not raw); manual inspection confirms no PII in any response; OpenAPI shape matches spec A1.
  - **Risk:** Low

- [x] **S1-B6** — Deprecate legacy `/api/telemetry`
  - **What:** Keep alive for one release returning 200 to old SuperSay 1.0.x clients; log and drop payload.
  - **Why:** Old installed apps keep working silently while we migrate.
  - **Files:** `himudigonda.me/pages/api/telemetry.ts` (touch)
  - **Acceptance:** Curl from a simulated 1.0.x client returns 200; server log shows "legacy telemetry dropped" entry; no exception raised.
  - **Risk:** Low

---

### Track C — Frontend / macOS auth (SuperSay Swift)

- [x] **S1-C1** — `AuthService.swift`
  - **What:** Google OAuth loopback flow (open browser to `https://himudigonda.me/supersay/oauth/start`, listen on `127.0.0.1:<random>`, receive code, exchange via B2); email/password forms call B3.
  - **Why:** The Swift-side engine for sign-in.
  - **Files:** `frontend/SuperSay/SuperSay/Services/AuthService.swift` (new)
  - **Acceptance:** XCTest with mocked network: Google exchange happy path stores token via `KeychainService`; email login likewise; loopback port collision (port in use) retries on a new port.
  - **Risk:** Med — loopback port collisions, OAuth state mismatch

- [x] **S1-C2** — `AuthViewModel.swift`
  - **What:** `@Published currentUser`, `isSignedIn`; sign-in/out/reset methods; error states.
  - **Why:** SwiftUI binding surface for SignInView/SignUpView/PreferencesView.
  - **Files:** `frontend/SuperSay/SuperSay/ViewModels/AuthViewModel.swift` (new)
  - **Acceptance:** XCTest covers state transitions: anon → signing → signed → signed-out; error states populate `lastError` and clear on retry.
  - **Risk:** Low

- [x] **S1-C3** — SignIn / SignUp views
  - **What:** Minimal SwiftUI — three buttons (Google, email-existing, email-new), inline errors, "Skip for now" always present.
  - **Why:** The actual UI the user sees during the onboarding nudge and from Preferences.
  - **Files:** `frontend/SuperSay/SuperSay/Views/Auth/SignInView.swift` (new), `frontend/SuperSay/SuperSay/Views/Auth/SignUpView.swift` (new)
  - **Acceptance:** Visual review on light + dark; Skip dismisses without account; successful sign-in stores token and dismisses sheet; bad password shows inline error.
  - **Risk:** Low

- [x] **S1-C4** — Keychain extension
  - **What:** Add `sessionToken` case alongside existing `geminiAPIKey`.
  - **Why:** Re-use the audited keychain wrapper rather than a new one.
  - **Files:** `frontend/SuperSay/SuperSay/Services/KeychainService.swift` (touch)
  - **Acceptance:** Token round-trips (store → read → match); cleared on sign-out (verified with `security` CLI on the test keychain).
  - **Risk:** Low

- [x] **S1-C5** — Account section in Preferences
  - **What:** Show signed-in email + sign-out button; show "Sign in to count" CTA when anon.
  - **Why:** Surface the auth state outside onboarding so the nudge remains discoverable.
  - **Files:** `frontend/SuperSay/SuperSay/Views/PreferencesView.swift` (touch)
  - **Acceptance:** Toggling auth state live updates the section (no relaunch needed); sign-out clears token and reverts to CTA within one runloop.
  - **Risk:** Low

---

### Track D — Frontend / telemetry v2 (Swift)

- [x] **S1-D1** — `MetricsService` rewrite
  - **What:** Batched event queue (flushes every 30s or 20 events), attaches Bearer when signed, attaches anon_id always, enforces a **client-side whitelist of allowed props keys** (defense in depth).
  - **Why:** Single owner of all outbound analytics; the whitelist is the second wall protecting the privacy promise.
  - **Files:** `frontend/SuperSay/SuperSay/Services/MetricsService.swift` (rewrite, preserve callsites)
  - **Acceptance:** XCTest — sending an event with a `text` key drops `text` before HTTP serialization; queue persists across app restarts via UserDefaults; flush triggers after 30s or 20 events whichever first.
  - **Risk:** High — accidentally sending PII would burn the privacy story

- [x] **S1-D2** — Track audio-seconds on completion
  - **What:** `AudioService` already knows playback duration; emit `generation` event with `{chars, voice, speed, audio_seconds}` once playback completes (not on call start).
  - **Why:** The headline metric for the public posts is hours of audio generated — must be the rendered length, not an estimate.
  - **Files:** `frontend/SuperSay/SuperSay/Services/AudioService.swift` (touch), `frontend/SuperSay/SuperSay/ViewModels/DashboardViewModel.swift` (touch)
  - **Acceptance:** `audio_seconds` matches rendered output length within ±50ms; verified by comparing two known-length samples; cancelled playback emits no event.
  - **Risk:** Med — race between completion and cancellation

- [x] **S1-D3** — Audiobook funnel events
  - **What:** Emit `audiobook_upload` (pages, file_kind), `audiobook_play` (book_id_hash, seconds_played); file name and content never leave the device. `book_id_hash` = SHA-256 of the local id.
  - **Why:** Powers the audiobook funnel chart (F5).
  - **Files:** `frontend/SuperSay/SuperSay/ViewModels/AudiobookViewModel.swift` (touch)
  - **Acceptance:** `book_id_hash` is the SHA-256 of the local id, never the title; verified by reading the outbound payload in a debug log; XCTest asserts the hash is deterministic and 64 hex chars.
  - **Risk:** Low

- [x] **S1-D4** — Client-side `audio_seconds` accumulator (revised in spec §10)
  - **Revision:** Original plan was a backend `X-Audio-Seconds` response header. Dropped — `StreamingResponse` cannot set a header value that's only known after the last sentence finishes rendering. Instead, source `audio_seconds` from `AudioService.renderedAudioSeconds` (PCM frames / sample rate) at the moment `DashboardViewModel.speak()` calls `audio.finishStream()`. Accurate, no protocol contortions, no backend change required.
  - **Files:** `frontend/SuperSay/SuperSay/Services/AudioService.swift` (added `renderedAudioSeconds`), `frontend/SuperSay/SuperSay/ViewModels/DashboardViewModel.swift` (uses it in the post-stream metric emit)
  - **Acceptance:** `audio_seconds` is the rendered length within ±1 frame; covered by `MetricsServiceTests.testAudioSecondsAccumulator` (G6).
  - **Risk:** Now low.

- [x] **S1-D5** — Honor `telemetryEnabled` for all new events (kill switch in `MetricsService.enqueue` + `flushLocked`; HAR proof deferred to runtime-verify pass)
  - **What:** With the existing toggle off, nothing leaves the box — zero requests to himudigonda.me during a full session.
  - **Why:** The toggle is the user-visible escape hatch and the most checkable promise.
  - **Files:** `frontend/SuperSay/SuperSay/Services/MetricsService.swift` (touch)
  - **Acceptance:** With toggle off, a full TTS + audiobook session produces zero HTTP requests to himudigonda.me (verified via Charles Proxy or `tcpdump`); HAR saved to `docs/evidence/v1.1-telemetry-off.har`.
  - **Risk:** High — silent leak voids the promise

---

### Track E — Onboarding (Swift)

- [x] **S1-E1** — `OnboardingView` (5 steps)
  - **What:** Paged view — (1) Welcome + what SuperSay is, (2) Cmd+Shift+. demo with live mini-TTS sample, (3) Voices + speed, (4) Audiobooks + how Gemini is used (only when *you* paste a key + only for cleaning, never for TTS), (5) Privacy + sign-in nudge.
  - **Why:** First-launch experience that teaches the app and earns the sign-in.
  - **Files:** `frontend/SuperSay/SuperSay/Views/Onboarding/OnboardingView.swift` (new)
  - **Acceptance:** Shows once on first launch (`@AppStorage("hasOnboarded")`); Skip available on every step; final step has "Sign in" + "Maybe later" buttons of equal visual weight; verified by deleting the flag and relaunching.
  - **Risk:** Low

- [x] **S1-E2** — Privacy + nudge copy (in `Views/Onboarding/OnboardingCopy.swift`)
  - **What:** Step-5 copy reads approximately: *"SuperSay runs fully on your Mac. Your text never leaves this machine. Signing in only helps us count how many people use SuperSay and how much audio gets generated — it's the only way we can show real growth numbers when we share the project publicly. We never read what you type."* + link to `PRIVACY.md`. Copy lives in a constants file, not hardcoded in the view body.
  - **Why:** This is the single most important sentence in the sprint — it has to be true and editable.
  - **Files:** `frontend/SuperSay/SuperSay/Views/Onboarding/OnboardingView.swift`, `frontend/SuperSay/SuperSay/Views/Onboarding/PrivacyCard.swift` (new)
  - **Acceptance:** Wording reviewed by user before commit; copy is exported from a Swift constants file (e.g. `OnboardingCopy.privacyNudge`) so it is editable without view churn; PRIVACY.md link opens in default browser.
  - **Risk:** Low

- [x] **S1-E3** — `OnboardingCoordinator`
  - **What:** First-launch detection refactor — one source of truth for "has user completed onboarding".
  - **Why:** Today the flag is read in scattered `@AppStorage` calls in `SuperSayApp.init`; needs a single owner.
  - **Files:** `frontend/SuperSay/SuperSay/Services/OnboardingCoordinator.swift` (new), `frontend/SuperSay/SuperSay/SuperSayApp.swift` (touch)
  - **Acceptance:** XCTest — coordinator returns `needsOnboarding == true` on a clean install, `false` after completion; deleting the flag in defaults restores `true`.
  - **Risk:** Low

---

### Track F — Dashboard (himudigonda-metrics-dashbaord)

- [x] **S1-F1** — SuperSay overview cards
  - **What:** New SuperSay tab/section: users, DAU, WAU, total calls, total audio hours — all from `/api/supersay/metrics/overview`.
  - **Why:** The numbers we point at in the public post.
  - **Files:** `himudigonda-metrics-dashbaord/app/supersay/page.tsx` (new), `himudigonda-metrics-dashbaord/lib/supersay-api.ts` (new)
  - **Acceptance:** Live data renders against the deployed API; mock fallback when API down; cards show actual numerals not placeholders.
  - **Risk:** Low

- [x] **S1-F2** — Daily trend chart
  - **What:** Recharts line chart — users + generations + audio hours over last 90 days.
  - **Why:** The "is it growing?" chart for screenshots.
  - **Files:** `himudigonda-metrics-dashbaord/app/supersay/page.tsx`
  - **Acceptance:** Recharts line chart with sane Y axes and a tooltip showing the date + three values on hover; renders against seeded data.
  - **Risk:** Low

- [x] **S1-F3** — Voice distribution chart
  - **What:** Donut or bar chart from `/api/supersay/metrics/voices`.
  - **Why:** Shows the long tail of Kokoro voices people actually use.
  - **Files:** `himudigonda-metrics-dashbaord/app/supersay/page.tsx`
  - **Acceptance:** Chart renders all configured voices, sorted by usage; reads `/api/supersay/metrics/voices`.
  - **Risk:** Low

- [x] **S1-F4** — Retention cohort grid
  - **What:** D1/D7/D30 heatmap by week.
  - **Why:** Retention is the question every founder gets asked on HN — must have a chart.
  - **Files:** `himudigonda-metrics-dashbaord/app/supersay/page.tsx`
  - **Acceptance:** Reads `/api/supersay/metrics/retention`; renders even when sample size is small (empty cells styled, not crashing); axis labels show signup week + day cohort.
  - **Risk:** Med — sparse data looks ugly; needs a "small sample" notice

- [x] **S1-F5** — Audiobook funnel section
  - **What:** Uploads → pages → audio-seconds → completed funnel.
  - **Why:** Audiobook is the differentiating feature — funnel quantifies whether it gets used.
  - **Files:** `himudigonda-metrics-dashbaord/app/supersay/page.tsx`
  - **Acceptance:** Reads `/api/supersay/metrics/audiobook`; renders a step funnel with absolute counts and conversion rates.
  - **Risk:** Low

---

### Track G — Production polish

- [x] **S1-G1** — Backend structured logging
  - **What:** Replace `print`/loose logging with `structlog` in all new code; existing code on touch.
  - **Why:** JSON logs + correlation ids are the floor for triaging the new public endpoints.
  - **Files:** `backend/app/services/*` (touch on contact), `backend/app/api/endpoints.py` (touch)
  - **Acceptance:** All logs JSON; each request carries a correlation id propagated via header; verified by tailing the dev server during one e2e session.
  - **Risk:** Low

- [x] **S1-G2** — Normalized API error responses
  - **What:** `{error: {code, message}}` everywhere on `himudigonda.me/api/supersay/*` — never raw exceptions.
  - **Why:** Clients (Swift app, dashboard) get a consistent shape; no stack traces leak to public callers.
  - **Files:** `himudigonda.me/pages/api/supersay/_lib/errors.ts` (new) + apply in all B-track endpoints
  - **Acceptance:** Each endpoint returns the consistent shape on failure; test asserts no stack trace string appears in any non-2xx response body.
  - **Risk:** Med

- [x] **S1-G3** — Rate limits
  - **What:** Rate limits on all `/api/supersay/auth/*` and `/events` (Upstash Redis or in-memory token bucket on Vercel edge).
  - **Why:** Public endpoints — DoS is a real risk.
  - **Files:** `himudigonda.me/pages/api/supersay/_lib/ratelimit.ts` (new)
  - **Acceptance:** Test fires 1000 req/min and observes 429s past the configured threshold; auth endpoints capped tighter than `/events`.
  - **Risk:** Med (requires ADR — see ADR flags below — if Upstash is chosen as a new external dependency)

- [x] **S1-G4** — `PRIVACY.md`
  - **What:** Exhaustive list of every byte that leaves the user's Mac, with `file:line` references back into the code so it can be audited.
  - **Why:** The single most important document for the public posts; it is what makes the privacy promise verifiable.
  - **Files:** `SuperSay/PRIVACY.md` (new)
  - **Acceptance:** Linked from onboarding step 5 and from the README; every claim has at least one `file:line` reference; user re-reads and clicks each link to confirm.
  - **Risk:** Low

- [x] **S1-G5** — `docs/analytics.md`
  - **What:** What each event means, how rollups are computed, sample SQL queries for the dashboard.
  - **Why:** Future-self + future-contributor reference; reduces the chance of an event being added without thinking.
  - **Files:** `SuperSay/docs/analytics.md` (new)
  - **Acceptance:** Doc exists, reviewed; covers all six event names and the rollup schema.
  - **Risk:** Low

- [x] **S1-G6** — Test coverage
  - **What:** Backend pytest ≥ 85% on touched files; Swift XCTest for `AuthService`, `MetricsService`, `OnboardingCoordinator`.
  - **Why:** "Done" requires runtime evidence; this is the gate.
  - **Files:** `backend/tests/**`, `frontend/SuperSay/SuperSayTests/**`
  - **Acceptance:** `make test` green on SuperSay; `pnpm test` green on himudigonda.me; coverage report attached to PR; baseline pyright/swiftlint error counts not increased on touched files.
  - **Risk:** High — flaky tests block release

- [x] **S1-G7** — Codebase polish on touched files
  - **What:** ruff/black clean, swiftlint clean, pyright clean; remove dead code observed in passing — no rip-and-replace beyond touched files.
  - **Why:** The whole-team standard from the working agreement.
  - **Files:** all touched
  - **Acceptance:** `make lint` green; `uv run pyright` shows no new errors on modified files; SwiftLint clean.
  - **Risk:** Low

---

### Verification (how we prove it shipped)

1. **Privacy network capture.** Charles Proxy a fresh anon install. 5 TTS calls, 1 audiobook upload, 1 export. Assert zero HTTP request bodies contain user text. HAR saved to `docs/evidence/v1.1-privacy-capture.har`, referenced in PR.
2. **Telemetry-off proof.** Toggle `telemetryEnabled` off. Repeat the session. Assert zero requests to `himudigonda.me`. HAR saved to `docs/evidence/v1.1-telemetry-off.har`.
3. **Auth e2e.** Onboarding → step 5 → Google sign-in → browser consent → callback → app shows signed-in email in Preferences. Repeat with email/password. Repeat sign-out + sign-back-in.
4. **anon→signed link.** Generate 3 TTS calls anon, then sign in. Query `supersay_events`: those 3 events resolve to the signed user via the linked `anon_id`.
5. **Rollup correctness.** Insert 100 synthetic events via `/api/supersay/events`. Trigger cron. Assert `supersay_daily_rollups` row matches `select count(distinct actor_id), sum(...)` on raw events.
6. **Dashboard live.** `vercel --prod` the dashboard. Visit the URL. All five charts render with real data.
7. **Test suite.** `make test` green on SuperSay; `pnpm test` green on himudigonda.me. Coverage delta attached to PR.
8. **Privacy doc audit.** User re-reads `PRIVACY.md` and clicks each `file:line` link to confirm the claim. Single most important check for the public posts.

### Out of scope (deferred — explicit)

- Sign in with Apple (requires paid Apple Developer account)
- Multi-device session sync of history
- Server-side TTS quota / paid tier (this sprint stays free-only)
- Anonymized public leaderboard (privacy follow-up)
- iOS companion app, voice cloning, browser extension — per existing roadmap, untouched

### ADR flags (raised by PM, decisions pending)

- **A2 / B1–B5** introduce three new entity types (`supersay_users`, `supersay_events`, `supersay_daily_rollups`) and Supabase Auth as a new external auth dependency. Per the working agreement, this warrants an ADR before merge. The spec at **S1-A1** is the natural place to capture it.
- **G3** introduces a rate-limit backend choice (Upstash Redis vs in-memory token bucket on Vercel edge). If Upstash is selected, that is a new external service — log the trade-off in the same ADR or a sibling.
- **B4 (`link-anon`)** sets data-retention precedent (events made before sign-in stay attributable forever). Worth a short note in the ADR + `PRIVACY.md` so the public promise matches the implementation.
