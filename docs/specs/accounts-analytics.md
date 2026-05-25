# Spec — Accounts + Analytics + Onboarding (Sprint 1, v1.1)

**Status:** Draft for review (2026-05-25)
**Owner:** Himansh
**Related:** [`docs/SPRINTS.md`](../SPRINTS.md) Sprint 1, [`plans/add-a-sign-on-effervescent-bachman.md`](https://github.com/himudigonda) (alignment artifact)

---

## 1. Problem

SuperSay runs entirely on-device but currently emits anonymous UUID telemetry to a single endpoint (`himudigonda.me/api/telemetry`) backed by a JSON file. We cannot:

- Count distinct users (only devices) or measure retention.
- Quantify usage (no audio-seconds, no per-voice breakdown).
- Tell a credible growth story publicly on HN / Reddit / LinkedIn (numbers are crude and unverifiable).
- Justify an "optional sign-in" without explaining what we will and will not collect.

We also have no first-launch experience to teach the app, expose the privacy model, or explain how Gemini fits in (audiobook cleaning only, never TTS).

## 2. Goals

1. Optional, transparent **sign-in** (Google OAuth + email/password, Supabase Auth). Never gates functionality.
2. **Telemetry v2**: counts only — never text, never file contents, never audio. Whitelisted at both client and server edges.
3. **Onboarding** that teaches the app and ends with a sign-in nudge whose copy can be quoted verbatim in a HN post without embarrassment.
4. **Dashboard charts** that hold up to scrutiny: users, DAU/WAU, calls, audio-hours, voice distribution, D1/D7/D30 retention, audiobook funnel.
5. **Production polish** so the new public endpoints can survive a HN spike.

## 3. Non-goals (out of scope)

- Sign in with Apple (no paid Apple Developer account).
- Multi-device sync of history or settings.
- Server-side TTS / paid tier / quotas.
- Public anonymized leaderboard.
- iOS app, voice cloning, browser extension (existing roadmap, untouched).

## 4. Actor model

```
┌───────────────────────────┐
│ Anonymous user            │
│ anon_id: persistent UUID  │   ─── anon events ───►  /api/supersay/events
│ stored in AppStorage      │                          (no Authorization header)
│ (existing                 │
│  "anonymousUserID")       │
└─────────────┬─────────────┘
              │ Sign-in (optional)
              ▼
┌───────────────────────────┐
│ Signed user               │
│ user_id: Supabase auth.uid│   ─── signed events ─►  /api/supersay/events
│ session_jwt: Keychain     │                          (Authorization: Bearer <jwt>)
│ anon_id: linked once      │
└───────────────────────────┘
```

**Identity rules:**

- An `anon_id` is generated locally on first launch (already present in `MetricsService` via `@AppStorage("anonymousUserID")`). It is **opaque**; not derived from machine identifiers.
- On sign-in, the client calls `POST /api/supersay/auth/link-anon` with the anon_id. The server attaches it to `supersay_users.anon_id` (single value, last writer wins — see §10 edge cases).
- After link, events sent with either the bearer JWT *or* the anon_id resolve to the same `user_id` during rollup computation. We do **not** rewrite the historical raw event rows; the rollup query handles the resolution.
- Sign-out clears the JWT from Keychain. The `anon_id` persists. Sign-in again with a different account would re-link — see §10 for the conflict rule.

## 5. Event schema

One row in `supersay_events` per emitted event.

| Column        | Type          | Notes                                                                                      |
|---------------|---------------|--------------------------------------------------------------------------------------------|
| `id`          | bigserial PK  | Surrogate                                                                                  |
| `actor_id`    | text not null | `user_id` if signed, else `anon_id`                                                        |
| `is_signed`   | bool not null | Mirrors which lane the event came in on; lets us compute signed vs anon usage without a JOIN |
| `event`       | text not null | Enum (see §5.1)                                                                            |
| `ts`          | timestamptz   | Server-side `now()` at insert (we do **not** trust client ts)                              |
| `app_version` | text          | Sent by client, validated against regex `^[0-9]+\.[0-9]+\.[0-9]+$`                         |
| `platform`    | text          | Enum: `macOS` (only valid value for v1.1)                                                  |
| `props`       | jsonb         | Whitelisted keys only (see §5.2)                                                           |

Indexes: `(actor_id, ts desc)`, `(event, ts)`, `(date(ts))` for rollup query.

### 5.1 Event names (closed enum)

| Name              | Emitted when                                  | Required props                                        |
|-------------------|-----------------------------------------------|-------------------------------------------------------|
| `app_launch`      | `SuperSayApp.init()`                          | (none)                                                |
| `generation`      | TTS playback completes naturally              | `chars`, `voice`, `speed`, `audio_seconds`            |
| `export`          | Export-to-Desktop succeeds                    | `audio_seconds`                                       |
| `audiobook_upload`| Audiobook upload completes                    | `pages`, `file_kind` (enum: `pdf`/`txt`/`epub`)       |
| `audiobook_play`  | Audiobook playback session ends               | `book_id_hash`, `seconds_played`                      |
| `gemini_clean`    | Gemini cleaning call completes                | `pages`, `chars_out` (count only — never the cleaned text) |

Any event with an unrecognized `event` value is dropped at the API edge with `dropped += 1`.

### 5.2 Props whitelist (closed)

Allowed keys, validated at *both* client (defense-in-depth) and server (authoritative):

```
chars              integer  >= 0    (count of characters in input text — never the text itself)
voice              text     enum    (one of the 8 Kokoro voice ids)
speed              float    [0.5, 2.0]
volume             float    [0.0, 1.5]
audio_seconds      float    >= 0
pages              integer  >= 0
file_kind          text     enum    ('pdf'|'txt'|'epub')
book_id_hash       text     /^[a-f0-9]{64}$/   (SHA-256, never a title or filename)
chars_out          integer  >= 0
seconds_played     float    >= 0
```

Any other key is **dropped** and counted. The server's response includes `{accepted, dropped, dropped_keys: [...]}` so the client can log if the schema drifts.

### 5.3 What is forbidden (privacy floor)

- Raw text (input, output, cleaned, ocr'd) — **never** crosses the wire.
- File names, paths, file contents.
- Audio data.
- Free-form `props` keys.
- Client IP beyond what the request itself reveals (Vercel logs strip after 30 days — see PRIVACY.md G4).
- Email, name (held in Supabase Auth only; not duplicated into `supersay_events`).

## 6. API contracts

All endpoints live under `https://himudigonda.me/api/supersay/`. Errors use the normalized shape from G2:

```json
{ "error": { "code": "string_enum", "message": "human-readable" } }
```

`code` values: `unauthorized | rate_limited | bad_request | not_found | conflict | server_error`.

### 6.1 Telemetry ingest

**`POST /api/supersay/events`**

Auth: optional `Authorization: Bearer <supabase_jwt>`. If absent, body must contain `anon_id`.

Request:
```json
{
  "anon_id": "uuid-v4 (optional if bearer present)",
  "app_version": "1.1.0",
  "platform": "macOS",
  "events": [
    { "event": "generation", "props": {"chars": 142, "voice": "af_bella", "speed": 1.0, "audio_seconds": 12.4} },
    { "event": "app_launch", "props": {} }
  ]
}
```

Response 200:
```json
{ "accepted": 2, "dropped": 0, "dropped_keys": [] }
```

Rate limit: **60 events/min/actor_id** (G3). 429 returns `{error: {code: "rate_limited", ...}}`. Body cap: 50 events per request.

### 6.2 Auth — Google OAuth (loopback)

Desktop loopback flow with **PKCE** (no client secret in the macOS app).

1. App generates `code_verifier` + `code_challenge` (S256), opens browser to:
   `https://himudigonda.me/supersay/oauth/start?challenge=<challenge>&port=<loopback_port>&state=<state>`
2. Server redirects to Google's OAuth consent with appropriate `redirect_uri = https://himudigonda.me/supersay/oauth/callback`.
3. Google returns `code` to the callback. Server stores `(state -> code, verifier)` keyed by state for 60s.
4. App polls `POST /api/supersay/auth/google/exchange` with `{state, code_verifier}`.
5. Server exchanges with Google using the verifier, fetches user profile, upserts into Supabase Auth, returns `{access_token, refresh_token, user: {id, email, display_name}}`.

State is single-use, expires in 60s. If the loopback port is occupied, the client retries on a new port (the redirect URL is server-controlled; only `state` is round-tripped).

**`POST /api/supersay/auth/google/exchange`**
```json
// Request
{ "state": "abc123", "code_verifier": "..." }
// Response 200
{ "access_token": "...", "refresh_token": "...", "user": {"id":"uuid","email":"a@b.com","display_name":"A"} }
```

### 6.3 Auth — email/password

**`POST /api/supersay/auth/email/signup`** — body `{email, password}` (min 10 chars; Supabase Auth handles hashing).
**`POST /api/supersay/auth/email/login`** — body `{email, password}`.
**`POST /api/supersay/auth/email/request-reset`** — body `{email}`; Supabase emails a reset link.
**`POST /api/supersay/auth/email/confirm-reset`** — body `{token, new_password}`.

All return the same shape as 6.2 on success. Rate limit: **5 attempts/min/IP** on login + request-reset.

### 6.4 Link anon

**`POST /api/supersay/auth/link-anon`** (Bearer required)
```json
// Request
{ "anon_id": "uuid-v4" }
// Response 200
{ "linked": true, "previous_anon_id": null | "uuid" }
```

If `previous_anon_id` is non-null, the server logs a `link_conflict` event for manual review (rare; only when a user signs in on a second device with a different anon_id).

### 6.5 Public metrics (read-only)

All return JSON, cacheable for 5 minutes (`Cache-Control: public, max-age=300`). No auth.

- **`GET /api/supersay/metrics/overview`** → `{users_total, users_signed, dau, wau, generations_total, audio_seconds_total}`
- **`GET /api/supersay/metrics/daily?days=90`** → `[{date, users, signups, generations, audio_seconds}, ...]`
- **`GET /api/supersay/metrics/voices`** → `[{voice, generations, audio_seconds}, ...]` sorted desc
- **`GET /api/supersay/metrics/retention?weeks=12`** → cohort matrix (see F4 in SPRINTS.md)
- **`GET /api/supersay/metrics/audiobook`** → `{uploads, pages_total, audio_seconds_total, completed, completion_rate}`

All read from `supersay_daily_rollups` + views; never raw events. Each response includes `sample_size_warning: true` when underlying data is < 50 actors total (drives the F4 "preview" banner).

### 6.6 Legacy

**`POST /api/telemetry`** — kept alive for one release. Returns `200 {legacy: true}` without persistence. Logs `legacy_telemetry_dropped` once per `user_id` per day.

## 7. Auth lifecycle on the client

```
┌──────────┐  open  ┌──────────────────────┐  code  ┌──────────────────┐
│ SignIn   │───────►│ system browser       │───────►│ /oauth/callback  │
│ View     │        │ Google consent       │        │ stores state→code│
└────┬─────┘        └──────────────────────┘        └────────┬─────────┘
     │                                                       │
     │  loopback http://127.0.0.1:<port>/?state=...         │
     │◄──────────────────────────────────────────────────────┘
     │
     ▼
┌──────────────┐ POST /exchange {state, verifier}  ┌─────────────────┐
│ AuthService  │──────────────────────────────────►│ himudigonda.me  │
│              │◄──────────────────────────────────│  → Supabase     │
│ Keychain     │     {access, refresh, user}       │                 │
│  ←session_jwt│                                   └─────────────────┘
└──────┬───────┘
       │
       ▼
┌──────────────┐ POST /link-anon {anon_id} (Bearer)
│ AuthService  │──────────────────────────────────► himudigonda.me
└──────────────┘
```

Keychain entry: `com.himudigonda.SuperSay.session_token` (existing `KeychainService` extended with `sessionToken` case — task C4).

**Refresh:** access tokens valid for 1h; client refreshes via `POST /api/supersay/auth/refresh` (Supabase passthrough) on 401. Refresh token rotated. If refresh fails (401), client clears session and re-enters anon mode silently.

## 8. Server architecture

```
┌──────────────────────────────┐         ┌──────────────────────────┐
│ Next.js API routes (Vercel)  │         │ Supabase (free tier)     │
│ /api/supersay/events         │────────►│ supersay_events          │
│ /api/supersay/auth/*         │────────►│ auth.users               │
│ /api/supersay/metrics/*      │◄────────│ supersay_daily_rollups   │
│ /api/cron/supersay-rollup    │────────►│ supersay_retention_cohorts (view)│
└──────────────┬───────────────┘         └──────────────────────────┘
               │
               │ rate-limit (G3) — Upstash Redis or edge in-memory bucket
               ▼
        429 if exceeded
```

**RLS policy** (Supabase row-level security):
- `supersay_events` — `insert` policy: anon role can insert if `is_signed = false`; service_role can insert anything. No public `select`.
- `supersay_users` — `select` policy: service_role only. **Public must never list users.**
- `supersay_daily_rollups` — `select` policy: public (anon role) — these are aggregate-only rows.

## 9. Privacy model (the contract)

The promise we make publicly:

> **SuperSay runs fully on your Mac. Your text never leaves this machine. We collect counts only — how many people use SuperSay and how much audio gets generated. We never read what you type.**

This spec exists in part to make that promise auditable. **Anything that contradicts §5.3 is a bug.**

Enforcement layers (defense in depth):

1. **Client whitelist** in `MetricsService` (task D1) — drops unknown keys before HTTP serialization. Failing this would only be caught by network capture, hence:
2. **Server whitelist** in `/api/supersay/events` (task B1) — re-drops unknown keys before insert. Authoritative.
3. **Schema constraint** in Supabase — `props` is `jsonb` but validated via a CHECK constraint on the column to a max key set (added in A2).
4. **Audit trail** — `PRIVACY.md` (G4) lists every line of code that crosses the network boundary with `file:line` refs.
5. **Toggle** — `telemetryEnabled` (existing) hard-blocks `MetricsService.flush()`. Verified by HAR capture (task D5).

## 10. Edge cases

| Case                                                           | Resolution                                                                                         |
|----------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| User signs in on Mac A (anon_A → user_X), then on Mac B (anon_B). | `link-anon` overwrites `supersay_users.anon_id = anon_B`. We log `link_conflict`. Rollups dedupe by `user_id`. Events from anon_A before sign-in remain attributed to user_X via a `signed_users_anon_history` view (computed in rollup). |
| User signs in, then signs out, then signs in as a different account. | Session token cleared on sign-out. `anon_id` persists. New sign-in re-links — last writer wins.    |
| Two users share the same anon_id (e.g., copied AppStorage).    | Acceptable in v1.1 — rollups count `distinct actor_id`; this counts as one. Documented in PRIVACY.md. |
| Network down, events queued.                                   | `MetricsService` persists the queue to `UserDefaults` ("metrics_outbox"); next flush retries. Outbox capped at 200 events; older dropped. |
| Telemetry toggle off, then on later.                           | Events generated while off are **never persisted** (not even locally). When toggled on, the next event onwards is sent. |
| Onboarding skipped halfway.                                    | `hasOnboarded = false`. Onboarding re-appears on next launch. Sign-in skipped is recorded as `app_launch` event with `props.onboarding_skipped = true` *(removed — props whitelist forbids this; instead, no explicit signal. We only know via "no sign-in within N days" in rollups.)* |
| Loopback port collision on Google sign-in.                     | Client retries on a new port (1024–65535 random). State token includes new port; server validates. |
| Refresh token revoked server-side.                             | Client gets 401 on refresh, clears session, falls back to anon mode silently. No user-visible error.|
| User opens onboarding step 5 and clicks the privacy link offline. | Link is a local `file://` to bundled `PRIVACY.md` first; falls back to `https://github.com/...` if bundle missing. |
| `book_id_hash` collision across users.                         | SHA-256 of local UUID — collision probability negligible. We never compare hashes across users.    |
| `/speak` cancelled mid-stream.                                 | No `generation` event emitted. (D2: only emit on natural completion.)                              |
| Audio seconds — how to source?                                 | **Decision (revises D4):** drop the `X-Audio-Seconds` response header idea. The backend cannot set the value in a header before streaming begins. Source `audio_seconds` from the client: `AudioService` accumulates PCM frames as they are scheduled; on `playbackCompleted`, compute `audio_seconds = framesScheduled / sampleRate`. This is the rendered length, not playback wall-clock. **Action for D4:** rename the task to "client-side audio_seconds accumulator on AudioService" and remove the backend header work. |

## 11. Test matrix

### Backend (himudigonda.me — Jest)

| Test                                                           | Asserts                                                                |
|----------------------------------------------------------------|------------------------------------------------------------------------|
| `events.test.ts`: payload with `text` key                      | `dropped >= 1`, `dropped_keys` includes `text`, row inserted without it |
| `events.test.ts`: bearer JWT                                   | Event row has `is_signed=true`, `actor_id=user.id`                    |
| `events.test.ts`: anon_id only                                 | Event row has `is_signed=false`, `actor_id=anon_id`                   |
| `events.test.ts`: 61st event in a minute                       | 429, `{error: {code: "rate_limited"}}`                                |
| `events.test.ts`: malformed JSON                               | 400, no insert                                                        |
| `google.test.ts`: state replay                                 | 400 on second use of same state                                       |
| `google.test.ts`: expired state                                | 400 after 60s                                                         |
| `link-anon.test.ts`: second link                               | `previous_anon_id` non-null; `link_conflict` logged                   |
| `metrics/overview.test.ts`: no PII                             | Response JSON contains no email, no anon_id, no user_id              |
| `metrics/retention.test.ts`: sparse data                       | `sample_size_warning: true` when actors < 50                          |
| `errors.test.ts`: any 5xx                                      | Response body has no `stack` key, no file paths                       |

### Frontend (Swift — XCTest)

| Test                                                           | Asserts                                                                |
|----------------------------------------------------------------|------------------------------------------------------------------------|
| `MetricsServiceTests.testDropsTextKey`                         | Outbound payload does not include `"text"` even when caller passes it |
| `MetricsServiceTests.testRespectsToggle`                       | With `telemetryEnabled=false`, no URLSession task is created           |
| `MetricsServiceTests.testQueuePersists`                        | After app restart simulation, queued events flush on next call         |
| `MetricsServiceTests.testBatchFlushAt20`                       | 20th event triggers immediate flush                                    |
| `MetricsServiceTests.testFlushAt30s`                           | After 30s tick, flush happens                                          |
| `AuthServiceTests.testGoogleHappyPath`                         | Stores token, posts link-anon                                          |
| `AuthServiceTests.testEmailLogin`                              | Stores token                                                           |
| `AuthServiceTests.testSignOutClearsKeychain`                   | After sign-out, Keychain read returns nil                              |
| `AuthServiceTests.testLoopbackPortCollision`                   | Picks new port on bind error                                           |
| `OnboardingCoordinatorTests.testFirstLaunch`                   | `needsOnboarding == true` on clean install                             |
| `OnboardingCoordinatorTests.testAfterCompletion`               | `needsOnboarding == false` after `markCompleted()`                     |
| `AudioServiceTests.testAudioSecondsAccumulator`                | `accumulatedAudioSeconds` matches sum of buffer durations (±0.001s)    |

### Privacy proof (manual, recorded in PR)

- **HAR-1**: Full session, telemetry on. Inspect every request body — no `text`, no file names, no audio.
- **HAR-2**: Full session, telemetry off. Zero requests to `himudigonda.me`.

## 12. Migration plan (legacy → v2)

1. Ship v1.1 with `MetricsService` posting to `/api/supersay/events` (new). Legacy `/api/telemetry` stays alive returning 200.
2. After 30 days of v1.1 adoption (target ≥ 80% of active installs), set `/api/telemetry` to log-only.
3. After 60 days, decommission `/api/telemetry`.

No data migration from the legacy JSON file — it's anonymous device counts only and not retroactively useful. We will however include a one-line note on the dashboard: *"Numbers shown begin 2026-05-XX, when v1.1 telemetry shipped. Earlier device counts available on request."*

## 13. ADR triggers (will be authored separately)

Three decisions warrant an ADR per the working agreement (PM flagged these on sprint planning):

1. **ADR-001:** New entities (`supersay_users`, `supersay_events`, `supersay_daily_rollups`) + Supabase Auth as a new external auth dependency.
2. **ADR-002:** Rate-limit backend — Upstash Redis vs in-memory edge token bucket (only if Upstash is chosen, since that adds a dependency).
3. **ADR-003:** Pre-sign-in event attribution policy (events made before sign-in stay attributable to the user forever via `link-anon`). This sets data-retention precedent and must match `PRIVACY.md`.

## 14. Open questions

None remaining. All locked in alignment session (see SPRINTS.md "Locked decisions" table).

## 15. References

- `docs/SPRINTS.md` — Sprint 1 task breakdown
- `docs/architecture.md` — existing system architecture
- `frontend/SuperSay/SuperSay/Services/MetricsService.swift` — current telemetry implementation (to be rewritten in D1)
- `backend/app/api/endpoints.py` — current `/speak` route (touched in D4 → now scoped client-side)
- `PRIVACY.md` (to be written in G4) — the public-facing audit trail
