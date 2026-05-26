# Testing — SuperSay v2.0.1

This document explains how SuperSay is tested across the three repos
that make up the product. It exists so the next contributor (or future
self) doesn't have to reconstruct the rationale by reading source.

If you change one of the **four privacy-load-bearing files** listed
below, you MUST update its red-team test in the same PR. No exceptions.

## The four files the privacy promise depends on

| File | Repo | Layer |
| :--- | :--- | :--- |
| `frontend/SuperSay/SuperSay/Services/MetricsService.swift` | SuperSay | client whitelist (Props.allowedKeys + Event.allowedNames) |
| `lib/supersay-validate.js` | himudigonda.me | server whitelist + event-name closed set |
| `pages/api/supersay/events.js` | himudigonda.me | enforcement at the ingestion edge |
| `frontend/SuperSay/SuperSay/Services/AuthService.swift` | SuperSay | PKCE + bearer attachment |

Each of these has a **red-team test file** that constructs adversarial
payloads (text leak keys, Cyrillic-look-alike key names, base64 prose,
reserved-key collisions, out-of-range values for allowed keys) and
asserts they're dropped. The byte-wise assertion in those files (that
serialized JSON of a cleaned event contains zero adversarial content)
is the single piece of CI we can point at when someone asks "how do you
know the analytics doesn't leak text?".

## The pyramid, per repo

### Backend — Python / FastAPI (`backend/`)

| Layer | Files | What it covers |
| :--- | :--- | :--- |
| Unit | `tests/test_audio_pipeline.py`, `test_audiobook.py`, `test_audiobook_store.py`, `test_tts.py`, `test_logging.py`, `test_config.py`, `test_gemini_cleaner.py` | Audio + TTS + DB + logging + config |
| Property | `tests/test_properties.py` | Sentence-splitter reassembly, audio clip range, log formatter under arbitrary extras (200 examples / property in dev, 1000 in nightly) |
| Contract | `tests/test_correlation.py`, `tests/test_streaming_contract.py` | `X-Correlation-ID` on 2xx/4xx/5xx, `/speak` RIFF/WAV envelope, `/health` JSON shape |
| Integration | `tests/test_api.py`, `tests/test_audiobook.py` | FastAPI TestClient end-to-end, audiobook lifecycle |

Run:
```bash
cd backend
uv run pytest -q                # 161 tests, ~7s
uv run pytest --cov=app         # coverage report (currently ~73% total; 100% on logging/config)
```

### Swift — macOS app (`frontend/SuperSay/`)

| Layer | Files | What it covers |
| :--- | :--- | :--- |
| Unit | `SuperSayTests/SuperSayTests.swift`, `MetricsServiceTests.swift`, `OnboardingCoordinatorTests.swift`, `AuthServiceTests.swift` | Text sanitisation, props whitelist, onboarding flag, PKCE helpers |
| Red-team | `SuperSayTests/MetricsServiceRedTeamTests.swift` | 13 adversarial cases against the props whitelist. **Load-bearing.** |
| Integration | `SuperSayTests/AuthServiceIntegrationTests.swift` | URLProtocol-stubbed HTTP for emailLogin/Signup/PasswordReset/linkAnon |
| State machine | `SuperSayTests/AuthViewModelStateMachineTests.swift` | Anon → signing → signed → signed-out, Keychain persistence/restore |

Run:
```bash
xcodebuild test -project frontend/SuperSay/SuperSay.xcodeproj \
  -scheme SuperSay \
  -destination 'platform=macOS,arch=arm64'
# 52 test cases (~10s when the test runner is healthy)
```

**Known flake:** the Xcode test runner can hang on the host machine
with `The test runner hung before establishing connection`. This is an
Xcode/CoreSimulator issue (not a code issue) — restart Xcode or reboot.
CI runners on macos-14 are clean.

### himudigonda.me — Next.js API routes

| Layer | Files | What it covers |
| :--- | :--- | :--- |
| Unit | `lib/__tests__/supersay-validate.test.js` | Server-side whitelist + event-name set |
| Red-team | same file (38 cases) + `pages/api/supersay/__tests__/events.test.js` (17 cases) | Adversarial inputs dropped; SQL injection in actor_id passed as parameterised value; rate limit fires at 61 req/min |
| Integration | `pages/api/supersay/auth/__tests__/{email,google,link-anon}.test.js` (29 cases) | Email/Google/link-anon mocked against Supabase auth + DB |
| Contract | `pages/api/supersay/metrics/__tests__/metrics.test.js` (18 cases) | Each `/metrics/*` returns documented shape, `Cache-Control: public, max-age=300`, no PII regex match |
| Cron + legacy | `pages/api/cron/__tests__/supersay-rollup.test.js` (8) + `pages/api/__tests__/telemetry.test.js` (6) | Cron idempotence + auth, legacy 1.0.x endpoint always 200 |

Run:
```bash
cd himudigonda.me
pnpm test                   # 116 tests, ~1s
pnpm test:coverage          # with coverage report
pnpm test:mutation          # stryker on the privacy modules (slow)
```

### Dashboard — Next.js

| Layer | Files | What it covers |
| :--- | :--- | :--- |
| Unit | `src/lib/__tests__/supersay-api.test.js` (10 cases) | axios-mocked: every endpoint hit on documented path, query params forwarded, env override honored, parallel fetch shape correct |

Run:
```bash
cd ../himudigonda-metrics-dashbaord
pnpm test                   # 10 tests, <1s
```

## Coverage policy

From the global working agreement: 85% on services, 80% on routes,
95% on pure utilities. Plus **100% line + branch coverage on the four
privacy/auth-critical files**.

Current state:
- `backend/app/core/logging.py`: 100%.
- `backend/app/core/config.py`: 100%.
- `backend/app/services/audio.py`: 95%.
- `lib/supersay-validate.js`: enforced ≥ 100% via Jest `coverageThreshold` in `jest.config.js`.
- `pages/api/supersay/events.js`: enforced ≥ 90% lines / 75% branches.
- `src/lib/supersay-api.js`: enforced ≥ 95% via Vitest threshold.

CI runs `pnpm test:coverage` / `uv run pytest --cov` and breaks the
build if floors are crossed downward.

## Mutation testing

Scoped tight so a full run completes in 2-3 minutes locally; not
gated on PR, runs nightly.

| Repo | Tool | Scope |
| :--- | :--- | :--- |
| backend | `mutmut` | `app/api/middleware.py`, `app/services/audio.py` |
| himudigonda.me | `stryker` (`@stryker-mutator/core` + jest-runner) | `lib/supersay-validate.js`, `pages/api/supersay/events.js` |

Run locally:
```bash
make test-mutation                  # backend (mutmut)
cd ../himudigonda.me && pnpm test:mutation   # stryker
```

Expected mutation score: ≥ 80% on the four critical files. A surviving
mutant on `lib/supersay-validate.js` means a privacy regression that
the unit tests don't catch — investigate, don't ignore.

## CI

Three GitHub Actions workflows, all PR-blocking:

| Repo | Workflow | Triggers |
| :--- | :--- | :--- |
| SuperSay | `.github/workflows/test.yml` | push/PR; backend on Ubuntu + Swift on macos-14 |
| himudigonda.me | `.github/workflows/supersay-tests.yml` | push/PR touching `lib/supersay-*` or `pages/api/supersay/**` |
| dashboard | `.github/workflows/test.yml` | every push/PR |

A nightly mutation workflow will be added once the first full local
run has settled and we know its true wall-clock cost on CI runners.

## When you add a new event

Adding a new event name or props key to the analytics surface requires
**three updates in the same PR**:

1. Add the key/event to `MetricsService.Props.allowedKeys` (Swift) AND
   `lib/supersay-validate.js::VALIDATORS` (JS). They MUST agree.
2. Extend `MetricsServiceRedTeamTests.swift::test_redTeam_allowedKeysWithAdversarialValues`
   with an adversarial value for the new key (out-of-range, wrong type,
   etc.) and assert it's dropped.
3. Extend `lib/__tests__/supersay-validate.test.js::whitelistProps - allowed keys`
   with the same adversarial case server-side.

If the new event ships without all three, the PR is incomplete.

## Test count at a glance

- Backend Python: **161** (was 93 pre-sprint).
- Swift macOS: **52** (was 20 pre-sprint).
- himudigonda.me JS: **116** (was 0 pre-sprint).
- Dashboard JS: **10** (was 0 pre-sprint).
- **Total: 339 tests** across the v2.0.1 ship vs. 113 before.
