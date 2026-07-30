# SuperSay for macOS

This is the frozen, final SuperSay macOS client. It is built with SwiftUI and
AppKit for macOS 14 or later, and it talks only to the speech service bundled
inside the app at `127.0.0.1:10101`.

SuperSay remains usable as a local text-to-speech and audiobook app, but it
does not receive new features. [Voqora](https://github.com/himudigonda/Voqora)
is the current supported product.

## What is in the app

| Area | Responsibility |
| --- | --- |
| `LaunchManager` | Extracts and starts the bundled speech service, then checks its local health endpoint. |
| `BackendService` | Streams speech requests to the local `/speak` service. |
| `AudioService` | Plays rendered audio through `AVAudioEngine`. |
| `AudiobookService` | Manages local audiobook upload, progress, playback, and resume requests. |
| `MetricsService` | Sends optional, counts-only product telemetry. It never includes selected text or document material. |
| `HistoryManager` | Keeps spoken-text history locally on the Mac. |
| `SystemService` | Applies the optional Spotify or Music volume-ducking preference. |

The primary SwiftUI surfaces are the reading dashboard, local Vault, audiobook
library, Preferences, onboarding, and the permanent legacy notice in
`SuperSayWindow`.

## Privacy and transition boundary

The core speech path stays on the Mac. SuperSay has no account, Google sign-in,
or email sign-in flow.

When optional telemetry is enabled, SuperSay sends a closed set of product-use
metadata to the Voqora analytics endpoint with `product: "supersay"`. It does
not send selected text, document content, filenames, audio, email, credentials,
or API keys. See [`../PRIVACY.md`](../PRIVACY.md) for the complete boundary.

The app can notice Voqora in the standard Applications locations and point the
person to the supported product. It never removes Voqora or SuperSay, and it
does not copy settings or files between them.

## Build and test

1. Create `Resources/SuperSayServer.zip` with `make backend` from the repository root.
2. Open `SuperSay.xcodeproj` in Xcode and run, or use `make app` for a Release build.

For normal validation, run `make test`. For the native suite, run
`make test-swift`. The latter intentionally starts one serial Xcode test host;
it disables background services, permission prompts, shortcut registration, and
update checks while tests run.
