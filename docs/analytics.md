# SuperSay — Analytics Pipeline

Operational reference for the v1.1 telemetry pipeline. Pair with `docs/specs/accounts-analytics.md` (the contract) and `PRIVACY.md` (the public-facing promise).

---

## 1. Pipeline at a glance

```
macOS app                Supabase                    Dashboard
─────────                ────────                    ─────────
MetricsService           supersay_events             /metrics/overview  ──► overview cards
 batches 20/30s   ──►    (raw, props whitelist)
 props whitelist
                         ▼ nightly cron
                         supersay_daily_rollups  ──► /metrics/daily     ──► trend chart
                                                     /metrics/voices    ──► donut
 AuthService             supersay_users               /metrics/retention ──► heatmap
 (optional)       ──►    (linked to auth.users)       /metrics/audiobook ──► funnel
                         supersay_retention_cohorts (view)
```

Two consumers, one source of truth:
1. **Raw events** (`supersay_events`) — append-only, retained 90 days, never queried by public endpoints.
2. **Daily rollups** (`supersay_daily_rollups`) — produced by the nightly cron, retained forever, sole input to the dashboard.

## 2. Event glossary

Each event row carries `actor_id`, `is_signed`, `event`, `ts`, `app_version`, `platform`, and a `props` JSON object (whitelisted keys only — see §3).

| Event              | Emitted when                                              | Required `props` keys                                    |
|--------------------|------------------------------------------------------------|----------------------------------------------------------|
| `app_launch`       | App starts (`SuperSayApp.init`)                            | (none)                                                   |
| `generation`       | TTS stream ends naturally (`DashboardViewModel.speak`)     | `chars`, `voice`, `speed`, `audio_seconds`              |
| `export`           | "Export to Desktop" succeeds (`AudioService.exportToDesktop`) | `audio_seconds`                                       |
| `audiobook_upload` | Audiobook estimate returns successfully                    | `pages`, `file_kind`                                    |
| `audiobook_play`   | Audiobook playback ends (natural or stop >5s)              | `book_id_hash`, `seconds_played`                        |
| `gemini_clean`     | Gemini cleaning call completes                             | `pages`, `chars_out`                                    |

Events outside this list are dropped at the API edge.

## 3. Props key whitelist

Verbatim from `MetricsService.Props.allowedKeys`:

| Key              | Type   | Constraint                                       | Used by                            |
|------------------|--------|--------------------------------------------------|------------------------------------|
| `chars`          | int    | `>= 0`                                           | `generation`                       |
| `voice`          | string | one of 8 Kokoro voices                           | `generation`                       |
| `speed`          | float  | `[0.5, 2.0]`                                     | `generation`                       |
| `volume`         | float  | `[0.0, 1.5]`                                     | reserved                           |
| `audio_seconds`  | float  | `>= 0`                                           | `generation`, `export`             |
| `pages`          | int    | `>= 0`                                           | `audiobook_upload`, `gemini_clean` |
| `file_kind`      | string | `pdf`, `txt`, `epub`                             | `audiobook_upload`                 |
| `book_id_hash`   | string | SHA-256 hex, 64 chars                            | `audiobook_play`                   |
| `chars_out`      | int    | `>= 0`                                           | `gemini_clean`                     |
| `seconds_played` | float  | `>= 0`                                           | `audiobook_play`                   |

Any other key is dropped *before* HTTP serialization (client) and *before* insert (server). Both sides log to `dropped_keys` so we'd notice schema drift.

## 4. Rollup formulas

Computed nightly by `pages/api/cron/supersay-rollup.ts` against `supersay_events`. All rollups are **idempotent on re-run** (we `INSERT ... ON CONFLICT DO UPDATE`).

### 4.1 `supersay_daily_rollups` (one row per UTC date)

| Column                  | Formula                                                                            |
|-------------------------|-------------------------------------------------------------------------------------|
| `date`                  | `date_trunc('day', ts)`                                                             |
| `unique_users`          | `COUNT(DISTINCT actor_id) FILTER (event = 'app_launch')`                            |
| `signed_users`          | `COUNT(DISTINCT actor_id) FILTER (is_signed)`                                       |
| `generations`           | `COUNT(*) FILTER (event = 'generation')`                                            |
| `exports`               | `COUNT(*) FILTER (event = 'export')`                                                |
| `total_chars`           | `SUM((props->>'chars')::int) FILTER (event = 'generation')`                         |
| `total_audio_seconds`   | `SUM((props->>'audio_seconds')::float) FILTER (event IN ('generation', 'export'))`  |
| `audiobook_uploads`     | `COUNT(*) FILTER (event = 'audiobook_upload')`                                      |
| `audiobook_plays`       | `COUNT(*) FILTER (event = 'audiobook_play')`                                        |
| `audiobook_pages`       | `SUM((props->>'pages')::int) FILTER (event = 'audiobook_upload')`                   |
| `audiobook_seconds`     | `SUM((props->>'seconds_played')::float) FILTER (event = 'audiobook_play')`          |
| `gemini_pages`          | `SUM((props->>'pages')::int) FILTER (event = 'gemini_clean')`                       |

### 4.2 `supersay_retention_cohorts` (view, signup-date × day-offset)

For each signup date `D`, for each offset `N ∈ {1, 7, 30}`:

```
retained(D, N) = COUNT(DISTINCT actor_id)
                 FROM supersay_events
                 WHERE date(ts) = D + N
                 AND actor_id IN (
                     SELECT actor_id FROM supersay_events
                     WHERE date(ts) = D AND event = 'app_launch'
                 )
```

The view also returns `cohort_size = COUNT(DISTINCT actor_id)` on day `D` so the dashboard can compute the percentage.

## 5. Public read endpoints

All read from `supersay_daily_rollups` + `supersay_retention_cohorts` view. Never touch raw events. Cacheable (`Cache-Control: public, max-age=300`).

| Endpoint                              | Returns                                                                                  |
|---------------------------------------|------------------------------------------------------------------------------------------|
| `/api/supersay/metrics/overview`      | `{users_total, users_signed, dau, wau, generations_total, audio_seconds_total}`          |
| `/api/supersay/metrics/daily?days=90` | `[{date, users, signups, generations, audio_seconds}, ...]`                              |
| `/api/supersay/metrics/voices`        | `[{voice, generations, audio_seconds}, ...]` sorted desc                                  |
| `/api/supersay/metrics/retention?weeks=12` | retention cohort matrix                                                              |
| `/api/supersay/metrics/audiobook`     | `{uploads, pages_total, audio_seconds_total, completed, completion_rate}`                |

Responses include `sample_size_warning: true` when fewer than 50 actors total — the dashboard shows a "preview" banner so sparse early-release charts don't look broken.

## 6. Sample queries (Supabase SQL editor)

### Total audio-hours generated (this week)

```sql
select round(sum(total_audio_seconds) / 3600.0, 1) as hours
from supersay_daily_rollups
where date >= current_date - interval '7 days';
```

### DAU trend (last 30 days)

```sql
select date, unique_users
from supersay_daily_rollups
where date >= current_date - interval '30 days'
order by date;
```

### Voice popularity (top 5)

```sql
select
  props->>'voice' as voice,
  count(*) as generations,
  round(sum((props->>'audio_seconds')::float) / 60.0, 1) as minutes
from supersay_events
where event = 'generation'
  and ts >= current_date - interval '30 days'
group by 1
order by 2 desc
limit 5;
```

### D7 retention by cohort week

```sql
select
  date_trunc('week', signup_date) as cohort_week,
  round(avg(retained_d7::float / nullif(cohort_size, 0)) * 100, 1) as d7_pct
from supersay_retention_cohorts
where signup_date >= current_date - interval '12 weeks'
group by 1
order by 1;
```

### Audiobook funnel

```sql
select
  sum(audiobook_uploads) as uploads,
  sum(audiobook_pages) as pages_processed,
  round(sum(audiobook_seconds) / 3600.0, 1) as listened_hours,
  sum(audiobook_plays) as completed_sessions
from supersay_daily_rollups
where date >= current_date - interval '30 days';
```

## 7. Adding a new event or prop

1. Update the spec at `docs/specs/accounts-analytics.md` §5.
2. Add the event name to `MetricsService.Event.allowedNames` (client).
3. Add the key + validator to `MetricsService.Props.allowedKeys` (client) — same shape as existing entries.
4. Update the server's whitelist in `himudigonda.me/pages/api/supersay/_lib/validate.ts`.
5. Add the column / aggregation to `supersay_daily_rollups` in a new migration.
6. Update this file (`docs/analytics.md`) — event glossary, props table, sample queries.
7. Update `PRIVACY.md` if the field has any privacy implication.

If you skip step 6 or 7, treat it as a bug.

## 8. Retention policy

| Data                            | Retention | Why                                                                |
|---------------------------------|-----------|--------------------------------------------------------------------|
| `supersay_events` (raw)         | 90 days   | Enough to re-run rollups if a formula needs fixing                 |
| `supersay_daily_rollups`        | Forever   | Aggregate-only, no PII, source of all dashboard charts             |
| `supersay_users`                | Until delete request | Required for sign-in to work; deleted on email request   |
| Vercel request logs              | 30 days  | Standard Vercel default; contains request IPs                      |

A nightly cleanup job hard-deletes `supersay_events` rows older than 90 days (`pages/api/cron/supersay-events-cleanup.ts`, future).

## 9. Where to look if numbers look wrong

- **DAU dropped overnight to zero** → rollup cron failed. Check Vercel cron logs and `supersay_daily_rollups.date` for the missing day.
- **Audio-seconds is 0 but generations is non-zero** → client is on a version older than v1.1 (sending only `chars`). Look at `app_version` distribution.
- **Retention shows 0% across the board** → either no users have hit Day-N yet, or the `signup_date` calculation is treating only the very first `app_launch` per user. Inspect `supersay_retention_cohorts` directly.
- **Whitelist drops suddenly spike** → schema drift or a new client field. Check the server's `dropped_keys` logs and the latest `MetricsService.Props.allowedKeys`.
