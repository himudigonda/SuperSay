# 🚀 Release Process

Standard release flow for SuperSay. Single source of truth — the Makefile + `scripts/ship.sh`.

## 1. Pre-release checks

- All sprint tasks for the next version checked off in [`docs/SPRINTS.md`](./SPRINTS.md).
- `CHANGELOG.md` has a section titled `### 🚀 SuperSay v<X.Y.Z> Changelog` at the top (the `ship.sh` script greps for this exact header).
- `backend/pyproject.toml` `version` and Xcode `MARKETING_VERSION` both equal `<X.Y.Z>`.
- `make test` green: `uv run pytest` and `xcodebuild test`.
- Cloud setup verified — see [`docs/setup-v1.1.md`](./setup-v1.1.md) for env vars, Supabase migration, Vercel cron.
- `gh` CLI authenticated (`gh auth status` should show "Logged in to github.com").

## 2. Build the DMG

```bash
make release VERSION=<X.Y.Z>
```

What it does:

1. **Nuke** — kills any running SuperSay process and removes the locally-installed app's user data (`~/Library/Application Support/com.himudigonda.SuperSay`) so the release build starts from a true cold state.
2. **Backend** — `scripts/compile_backend.sh` runs PyInstaller and packages the bundled server into `Resources/SuperSayServer.zip`.
3. **Xcode archive + DMG** — `scripts/create_dmg.sh` builds the Release configuration, ad-hoc signs, and produces `build/SuperSay-<X.Y.Z>.dmg`.

Inspect the DMG: mount it, drag SuperSay to `/Applications`, run `xattr -cr /Applications/SuperSay.app`, launch.

## 3. Verify the release build manually

- **First launch:** onboarding sheet appears.
- **TTS:** highlight text → `Cmd ⇧ .` → audio starts within ~200ms.
- **Telemetry on:** run a generation. Tail backend log (Preferences → Export Debug Logs) and confirm a structured JSON `http.request` entry appears with `path:"/speak"` and `status:200`.
- **Telemetry off:** toggle Anonymous Analytics off in Preferences → run a full TTS + audiobook session under a network capture (Charles or `tcpdump host himudigonda.me`). Expect zero requests to himudigonda.me.
- **Sign-in:** Preferences → Account → Sign in with Google. Confirm browser → consent → redirect → app shows signed-in email.
- **Live metrics:** `curl -s "https://www.himudigonda.me/api/supersay/metrics/overview?t=$(date +%s)"` and confirm the event count increased.

## 4. Ship

```bash
make ship VERSION=<X.Y.Z>
```

Runs `scripts/ship.sh` which:

1. Re-runs `make release` (idempotent if step 2 already passed).
2. Commits any local changes (no-op if the tree is clean — recommended state).
3. Pushes `main`.
4. Tags `v<X.Y.Z>` with the changelog section as the tag message.
5. Pushes the tag.
6. Creates a GitHub Release via `gh release create`, attaching the DMG and using the changelog section as the release notes.

## 5. After-ship checks

- Visit the GitHub release page, confirm the DMG asset is downloadable.
- Re-download from the release page, run `xattr -cr` on the extracted app, launch — should work end-to-end on a fresh machine.
- Monitor the metrics dashboard for the next 24 hours — first real v<X.Y.Z> events should appear within minutes; the next-day rollup confirms the pipeline.

## 6. Rollback

If something is broken in the wild:

```bash
gh release delete v<X.Y.Z> --yes
git tag -d v<X.Y.Z>
git push origin :refs/tags/v<X.Y.Z>
```

Then re-tag the previous green commit if you need to re-promote it. Telemetry-side: existing event rows are valid forever, so rolling back the app doesn't corrupt the dashboard.
