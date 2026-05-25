# SuperSay — Privacy

**Last reviewed:** 2026-05-25 (v1.1)
**Audience:** users, security researchers, anyone fact-checking a public post.

This document lists **every byte that leaves your Mac** when you use SuperSay, with a `file:line` reference so you can verify each claim against the open-source code. If you find anything in the codebase that contradicts this document, that is a bug — please open an issue.

---

## TL;DR

> **SuperSay runs fully on your Mac. Your text never leaves this machine. Signing in only helps us count how many people use SuperSay and how much audio gets generated — it's the only way we can show real growth numbers when we share the project publicly. We never read what you type.**

Network egress is limited to four destinations, three of which are off by default or under your control:

| Destination                                | When                                                                                | What is sent                                                                  | Can you turn it off?               |
|--------------------------------------------|--------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|------------------------------------|
| `localhost:10101` (bundled backend on your Mac) | Always while the app runs                                                       | Your text — for local-only TTS rendering. Never leaves your machine.          | No (it's how TTS works)            |
| `https://himudigonda.me/api/supersay/events` | When telemetry is enabled (default on)                                            | **Counts only.** Closed whitelist; see §3.                                     | Yes — Preferences → telemetry off  |
| `https://generativelanguage.googleapis.com` (Google Gemini) | Only if you paste a Gemini API key AND upload an audiobook                | The audiobook's *page text* (so Gemini can clean it). Routed via our backend on your Mac. | Yes — leave the Gemini key blank   |
| `https://api.github.com/repos/himudigonda/SuperSay/releases` | App-update check on launch + manual check                                  | Standard GitHub API GET — no body, just our repo URL                          | Skip update step on launch         |

That's it. There is no third-party analytics SDK, no crash reporter, no advertising network, no fingerprinting, no SDK we don't own.

---

## 1. The on-device backend (`localhost:10101`)

SuperSay's text-to-speech inference runs in a Python/ONNX server **bundled inside the app and started on your Mac** (`LaunchManager.swift` extracts it from the app bundle on first launch). It listens on `127.0.0.1:10101`, which is your own machine — packets never enter your router.

Code paths:

- Process bootstrap: `frontend/SuperSay/SuperSay/Services/LaunchManager.swift`
- HTTP client: `frontend/SuperSay/SuperSay/Services/BackendService.swift`
- Audiobook service base URL: `frontend/SuperSay/SuperSay/Services/AudiobookService.swift:6` (`http://127.0.0.1:10101`)
- Server entrypoint: `backend/app/main.py`, `backend/app/api/endpoints.py`

If you put a network sniffer between your Mac and your router, you will see exactly zero `/speak` requests cross the wire. Verify it with:

```
sudo tcpdump -i any -A 'host himudigonda.me or port 10101' | grep -v 127.0.0.1
```

## 2. Anonymous + signed identity

SuperSay generates a random UUID on first launch and stores it in `UserDefaults` (`anonymousUserID`). It is **opaque** — not derived from your machine, your hardware, your IP, or any identifier we could de-anonymize. It is the only identifier sent with telemetry until you choose to sign in.

If you sign in (optional — see §5), the anon UUID is linked to your account so your pre-sign-in counts still appear in the public total. The linkage is one-way: we never publish your anon UUID alongside your email, and the public dashboard only ever shows aggregate numbers.

Code path:

- Anon UUID source: `frontend/SuperSay/SuperSay/Services/MetricsService.swift:20` (`@AppStorage("anonymousUserID")`)
- Initialization: `frontend/SuperSay/SuperSay/Services/MetricsService.swift:32-34`
- Spec for the link rule: `docs/specs/accounts-analytics.md` §4 (Actor model) and §10 (edge cases)

## 3. Telemetry — the only thing we send to our own server

Endpoint: `POST https://himudigonda.me/api/supersay/events`
Default: on. Toggle in Preferences → privacy. When off, **zero requests** leave the app (see §3.1 below).

### 3.1 The closed whitelist

The client (`MetricsService.Props.allowedKeys`) and the server independently enforce a closed list of allowed `props` keys. Anything outside this list is dropped *before* HTTP serialization. The list, verbatim from the code:

```
chars              integer  >= 0    (number of characters — never the text itself)
voice              text     enum    (one of 8 Kokoro voice IDs)
speed              float    [0.5, 2.0]
volume             float    [0.0, 1.5]
audio_seconds      float    >= 0    (rendered audio length in seconds)
pages              integer  >= 0
file_kind          text     enum    ('pdf'|'txt'|'epub')
book_id_hash       text     SHA-256(local UUID) — 64 hex chars
chars_out          integer  >= 0
seconds_played     float    >= 0
```

Code references:

- Whitelist definition: `frontend/SuperSay/SuperSay/Services/MetricsService.swift:230-256`
- Whitelist enforcement (drops unknown keys): `frontend/SuperSay/SuperSay/Services/MetricsService.swift:260-269` (`Props.whitelist`)
- Closed event names: `frontend/SuperSay/SuperSay/Services/MetricsService.swift:197-200`
- HTTP send site (single egress point): `frontend/SuperSay/SuperSay/Services/MetricsService.swift:130-153`

### 3.2 What we explicitly **do not** send

- **Your text.** The `chars` key is the count, not the content. There is no field in the whitelist for text. The string you type is sanitized into `cleaned` in `DashboardViewModel.speak()` (`ViewModels/DashboardViewModel.swift:160`) and never passed to `MetricsService`.
- **File names or contents.** When you upload an audiobook PDF, only `pages` (integer) and `file_kind` (constant `"pdf"`) are sent. The filename, title, and content stay on your Mac. See `AudiobookViewModel.swift` `presentEstimate` block.
- **Audio.** No PCM/WAV/MP3 bytes ever leave the app.
- **Your IP beyond what HTTPS reveals.** Our hosting (Vercel) sees the request IP, like every web server in the world. We do not store it past 30 days of standard request logs.
- **Email, name, machine identifiers.** None of the above appear in the event payload. Your email lives in Supabase Auth if you signed in, and is *not* duplicated into the events table.

### 3.3 The kill switch

`MetricsService.enqueue` returns at line `frontend/SuperSay/SuperSay/Services/MetricsService.swift:86` if `enabled` is false. `flushLocked` drops the outbox at line 122 in the same condition. The toggle is `@AppStorage("telemetryEnabled")` (line 21). When off, **no event ever enters the queue, the outbox is wiped, and no HTTP request is created**.

Verify with: turn the toggle off, then run a full TTS + audiobook session under Charles Proxy. You should see zero requests to `himudigonda.me`. Sample HAR file: `docs/evidence/v1.1-telemetry-off.har` (added after each release).

## 4. Gemini cleaning (only when you opt in)

If — and only if — you paste a Gemini API key into Preferences and upload an audiobook, our on-device Python backend forwards the PDF's *extracted text* to Google's Gemini API for cleaning (remove citations, OCR scanned pages, etc.). The result is returned to the local backend and rendered by Kokoro, also on-device.

Code references:

- Gemini service: `backend/app/services/gemini_cleaner.py`
- API key storage: `frontend/SuperSay/SuperSay/Services/KeychainService.swift` (Keychain entry `com.himudigonda.SuperSay.gemini_api_key`)
- Pricing page: `https://ai.google.dev/gemini-api/docs/pricing`

We do not see this text. Google's API does — that is Google's privacy policy, not ours. If you don't want Google to see your PDFs, leave the Gemini key blank; audiobook cleaning will fall back to local heuristics.

## 5. Optional sign-in

Sign-in is **optional**. The app works identically whether you sign in or stay anonymous.

If you sign in (Google OAuth or email/password, both routed through `https://himudigonda.me/api/supersay/auth/*`), what we store about you:

| Field           | Source                            | Where it lives                                |
|-----------------|-----------------------------------|-----------------------------------------------|
| `id`            | Supabase Auth                     | `auth.users` (Supabase)                       |
| `email`         | Your sign-in                      | `auth.users` (Supabase)                       |
| `display_name`  | Google OAuth profile (if Google)  | `auth.users.user_metadata`                    |
| `anon_id`       | Your existing local UUID          | `supersay_users.anon_id` (Supabase)           |
| `created_at`    | Server clock                      | `supersay_users`                              |
| `last_seen_at`  | Updated on each event             | `supersay_users`                              |

We never publish the user list. RLS policies in Supabase restrict `supersay_users` reads to the service role only — the public-facing dashboard reads only the aggregate `supersay_daily_rollups` table.

Code references:

- Auth contracts: `docs/specs/accounts-analytics.md` §6
- Session token storage: Keychain `com.himudigonda.SuperSay.session_token` (`KeychainService.swift:8`)
- RLS rules: `himudigonda.me/supabase/migrations/*` (separate repo)

### 5.1 If you want to delete your account

Email `himudigonda@gmail.com` from your sign-in address and your row in `supersay_users` plus the corresponding `auth.users` row will be hard-deleted within 7 days. Events you generated remain in the rollups (aggregate counts, no PII) — they cannot be traced back to you once your user row is removed.

## 6. App-update check

On launch and when you click "Check for updates" the app sends a GET to:

```
GET https://api.github.com/repos/himudigonda/SuperSay/releases
```

Standard GitHub API. No body. No identifiers beyond a normal HTTPS request.

Code reference: `frontend/SuperSay/SuperSay/ViewModels/DashboardViewModel.swift:331`.

## 7. Audit it yourself

Every claim in this document is checkable by reading the code at the referenced files and line numbers. To audit live behaviour:

```
# Watch every byte SuperSay sends, line by line:
sudo tcpdump -i any -nn -s 0 -A 'host himudigonda.me or host generativelanguage.googleapis.com or host api.github.com'
```

Or use Charles / mitmproxy / Wireshark. If you see anything in those captures that contradicts §1–§6, please open an issue — it's a bug.

## 8. What changes between releases

Any change to network behaviour (new endpoint, new event, new field on the whitelist, etc.) requires:

1. An update to this file in the same commit.
2. A `file:line` reference for the new code.
3. The sprint task file (`docs/SPRINTS.md`) reflecting the change.
4. An entry in the changelog at release time.

If any of those are missing, treat it as a privacy regression.

## 9. Contact

- Issues: <https://github.com/himudigonda/SuperSay/issues>
- Direct: himudigonda@gmail.com

— *This document is part of the open source repository. Edit history is in `git log -- PRIVACY.md`.*
