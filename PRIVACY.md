# SuperSay v2.0.1 legacy-release privacy note

SuperSay is retired. This document describes the final `v2.0.1` release only.

## What stays on your Mac

- Text-to-speech inference runs through the bundled local backend at `127.0.0.1:10101`.
- Your spoken text, generated audio, local history, and document files are not sent to the SuperSay telemetry service.
- If you choose the audiobook-cleaning flow and provide a Gemini API key, extracted document text or page images are sent to Google Gemini for that requested task. Leave the key empty to avoid that optional cloud step.

## Optional telemetry

When **Anonymous Analytics** is enabled, the final release sends a batched request to:

```
POST https://himudigonda.me/api/voqora/events
```

Every request includes:

```
product: "supersay"
anon_id: locally generated random UUID
app_version, platform, event name, timestamp
```

The allowed aggregate event fields are character count, selected voice, speed, volume, generated-audio duration, page count, file type, a locally derived book hash, cleaned-character count, and listening duration. The client drops unknown fields before serializing a request. Spoken text, filenames, document content, audio, email, credentials, and API keys are not telemetry fields.

Turning analytics off prevents new events from entering the queue and clears queued telemetry. The client implementation is in [`MetricsService.swift`](./frontend/SuperSay/SuperSay/Services/MetricsService.swift).

## Other network requests

- The app may check the final SuperSay GitHub releases page for updates.
- The Voqora link in the legacy notice opens GitHub only when selected.
- Gemini use is optional and user-initiated as described above.

There is no SuperSay sign-in flow in `v2.0.1`.

If this document and the released source disagree, treat the source as authoritative and report the discrepancy in the Voqora repository.
