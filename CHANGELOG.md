# Changelog

## v2.0.1 — final legacy release

Released as SuperSay's last maintained build. This release is intentionally based only on the public `v2.0.0` source snapshot. It contains no private multilingual or successor work.

### Product status

- Makes the retirement status visible in the app, README, preferences, user guide, and release notes.
- Points people to Voqora as the current supported product without claiming that the two products are the same app.
- Detects a Voqora installation and explains that SuperSay can be removed manually after Voqora is confirmed working.
- Keeps SuperSay's local text-to-speech and audiobook capabilities available as a frozen legacy product.

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

The original public release that serves as the complete code baseline for `v2.0.1`. Its previous release history is intentionally not carried forward as an active roadmap or support commitment.
