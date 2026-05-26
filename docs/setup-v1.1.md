# SuperSay v1.1 — deploy setup checklist

One-time configuration to make accounts + analytics work. Free tier on every service.

---

## 1. Supabase

Project: the existing `himudigonda` Supabase project (shared with Sakshi).

- Migration: `himudigonda.me/supabase/migrations/0001_supersay_v1.sql` — already applied via the SQL Editor.
- Three tables: `supersay_users`, `supersay_events`, `supersay_daily_rollups`.
- One view: `supersay_retention_cohorts`.
- One function: `compute_supersay_rollup(target_date date)`.
- RLS:
  - `supersay_users`: service-role only (never publicly readable).
  - `supersay_events`: anon role can `insert`, service-role full access.
  - `supersay_daily_rollups`: anon role can `select` (public aggregate).

## 2. Google Cloud Console

Project: `SuperSay` under `himudigonda@gmail.com`.

- **APIs & Services → OAuth consent screen**
  - External + test mode.
  - Authorized domain: `himudigonda.me`.
  - Test user: `himudigonda@gmail.com`.
- **APIs & Services → Credentials → OAuth Client ID**
  - Type: **Desktop app**.
  - Name: `SuperSay macOS`.
- Copy the **Client ID** into `SuperSay/frontend/SuperSay/SuperSay/Info.plist` under the `SuperSayGoogleClientID` key (currently empty — paste yours).
- Copy the **Client secret** into Vercel only.

## 3. Vercel env vars (project: `himudigonda.me`)

Settings → Environment Variables → six rows. All scopes (Production, Preview, Development) checked.

| Key | Source |
|---|---|
| `SUPABASE_URL` | Supabase project → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase API Keys → publishable key (`sb_publishable_...`) |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase API Keys → secret key (`sb_secret_...`) |
| `GOOGLE_OAUTH_CLIENT_ID` | Google Cloud → Credentials → SuperSay macOS |
| `GOOGLE_OAUTH_CLIENT_SECRET` | Same as above |
| `CRON_SECRET` | `openssl rand -hex 32` |

## 4. Vercel cron

`himudigonda.me/vercel.json` already declares:

```json
{ "crons": [{ "path": "/api/cron/supersay-rollup", "schedule": "15 3 * * *" }] }
```

Vercel registers this automatically on deploy. Runs daily at 03:15 UTC. Idempotent — safe to manually trigger from the Vercel cron tab.

## 5. macOS app (SuperSay)

Required edit before shipping:

```
frontend/SuperSay/SuperSay/Info.plist
  → <key>SuperSayGoogleClientID</key>
  → <string>PASTE_YOUR_GOOGLE_CLIENT_ID_HERE</string>
```

The Client ID is the long string ending in `.apps.googleusercontent.com`. **Do not paste the secret** — that lives only on the server.

Build the release:
```bash
make release VERSION=1.1.0
```

Outputs a signed/notarized DMG in `dist/`.

## 6. Verification (post-deploy)

```bash
# 1. Backend live
curl -s https://www.himudigonda.me/api/supersay/metrics/overview | jq

# 2. Event ingest (round-trip a fake event)
curl -s -X POST https://www.himudigonda.me/api/supersay/events \
  -H 'content-type: application/json' \
  -d '{"anon_id":"test-uuid","app_version":"1.1.0","platform":"macOS","events":[{"event":"app_launch","props":{}}]}'
# expect: {"accepted":1,"dropped":0,...}

# 3. Privacy whitelist actually drops `text`
curl -s -X POST https://www.himudigonda.me/api/supersay/events \
  -H 'content-type: application/json' \
  -d '{"anon_id":"test-uuid","app_version":"1.1.0","platform":"macOS","events":[{"event":"generation","props":{"chars":10,"voice":"af_bella","speed":1.0,"audio_seconds":2.0,"text":"leak me"}}]}'
# expect: "dropped_keys":["text"] in response

# 4. Manually trigger the rollup
curl -s -X POST https://www.himudigonda.me/api/cron/supersay-rollup \
  -H "authorization: Bearer ${CRON_SECRET}"
```

## 7. Public dashboard

Repo: `../himudigonda-metrics-dashbaord`.
Deploys to Vercel automatically on push. Reads from `https://www.himudigonda.me/api/supersay/metrics/*`.

## 8. What's intentionally not configured

- Sign in with Apple — needs a paid Apple Developer membership.
- Upstash Redis for rate limiting — in-memory bucket is fine for v1.1 scale (ADR-002).
- Multi-device sync of TTS history — out of scope; on the roadmap.
