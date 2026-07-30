# Changelog

## v2.0.3 — resize-safe Voqora handoff

Hotfix for the final legacy release. The migration banner now reflows its
actions at narrow sidebar widths, and the preferences/developer footer is
reserved with a native safe-area inset instead of competing with the library
list during window resizing.

## v2.0.2 — final Voqora handoff

Released as SuperSay's last compatibility patch. It remains based only on the
public legacy source line and excludes every private successor change.

- Replaces the static migration link with a guided **Update to Voqora** action.
  The action obtains Voqora's official GitHub release metadata, accepts exactly
  one HTTPS DMG with GitHub's published SHA-256 digest, verifies the download,
  and opens it in Finder for an explicit drag to Applications.
- Keeps four clear migration paths in the app: the SuperSay story, the Voqora
  story, the active Voqora GitHub project, and the verified Voqora installer.
- Never installs, replaces, deletes, or changes Gatekeeper settings for either
  app. SuperSay remains removable only when the person has confirmed Voqora
  works for them.
- Adds reliable outbox acknowledgement IDs so a concurrent telemetry event is
  not accidentally discarded after another queued batch succeeds.
- Records installer download, verification, Finder-open, and failure signals
  as a handoff funnel, never as completed installations or unique people.

## v2.0.1 — final legacy release

Released as SuperSay's last maintained build. This release is intentionally based only on the public `v2.0.0` source snapshot and excludes every private successor change.

### Product status

- Makes the retirement status visible in the app, README, preferences, user guide, and release notes.
- Points people to Voqora as the current supported product without claiming that the two products are the same app.
- Detects a Voqora installation and explains that SuperSay can be removed manually after Voqora is confirmed working.
- Keeps SuperSay's local text-to-speech and audiobook capabilities available as a frozen legacy product.
- Removes SuperSay's obsolete self-update path. The app now presents the Voqora release, project, and product-story links directly instead of checking a frozen update channel.
- Makes backend extraction fail visibly when the bundled archive cannot be unpacked or made executable, rather than showing a false ready state.

### Accounts and privacy

- Removes the obsolete Google and email sign-in UI, related client code, and stale OAuth bundle configuration.
- Removes account language from onboarding and documentation.
- Continues optional counts-only telemetry with no spoken text, document contents, filenames, audio, email, credentials, or API keys.

### Analytics and migration measurement

- Sends legacy telemetry to the active Voqora analytics endpoint with `product: "supersay"`.
- Keeps SuperSay installations separate from Voqora installations. Portfolio totals are installation totals, not a claim of unique people.
- Preserves an anonymous opt-out control in Preferences.

### Test and release hygiene

- Runs the macOS test suite in one serial Xcode host and prevents background services, shortcut registration, update checks, and permission prompts during tests.
- Removes stale account-focused docs and development-only publishing paths.
- Documents the final DMG installation flow, including the scoped quarantine-removal command for an app bundle that macOS refuses to open normally.

## v2.0.0 — public source snapshot

The original public release that serves as the complete code baseline for the
final `v2.0.x` legacy line. Its previous release history is intentionally not
carried forward as an active roadmap or support commitment.
