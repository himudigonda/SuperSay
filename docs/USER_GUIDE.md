# SuperSay user guide

> SuperSay is retired at `v2.0.2`. It remains usable as a legacy release; [Voqora](https://github.com/himudigonda/Voqora/releases/latest) is the current supported product.

## Speak selected text

1. Select text in any app.
2. Press `Cmd + Shift + .` (the default shortcut).
3. SuperSay reads the selection using your chosen voice and speed.
4. Press `Cmd + Shift + /` to pause or resume, `Cmd + Shift + ,` to stop, and `Cmd + Shift + M` to export the last clip as a WAV file on your Desktop.

The shortcuts are configurable in Preferences. SuperSay needs macOS Accessibility permission to read a selection from another app.

## Voices and local history

SuperSay ships eight Kokoro voices. `af_bella` is the default. Choose a voice, speed, volume, and theme in Preferences.

The Vault stores spoken snippets locally on your Mac. It is not uploaded by SuperSay telemetry.

## Audiobooks

1. Open **Library → Audiobooks**, or drag a PDF onto a SuperSay window.
2. Review the estimate and start processing.
3. SuperSay creates narration using the bundled local TTS engine and saves playback progress locally.

Gemini cleaning is optional. If you choose it and provide your own Gemini key, document text or page images are sent to Google only for that requested cleaning step. The key is stored in your macOS Keychain. Without a key, SuperSay uses local cleanup instead.

## Privacy and retirement

There is no account or sign-in flow in this final release. Optional anonymous analytics send only an installation identifier, app version, event names, and whitelisted aggregate fields such as generated character count or audio duration. Spoken text, files, filenames, audio, email, credentials, and API keys are not telemetry.

See [PRIVACY.md](../PRIVACY.md) for the full final-release contract. SuperSay and Voqora record separate anonymous installation counts; they are not represented as a deduplicated people count.

## Move to Voqora

Install Voqora and confirm it works for you. Voqora can import compatible playback and appearance preferences when it finds SuperSay in `/Applications` or `~/Applications`. Once you are happy with Voqora, move SuperSay to Trash yourself. Neither app removes the other automatically.

## Troubleshooting

### “Initializing SuperSay…” remains on screen

Quit SuperSay and reopen it from `/Applications`. If the problem persists, use **Preferences → Export Debug Logs** and include the exported log when reporting the issue in the Voqora repository.

### The selected text is wrong

Click the source app, select the text again, then wait a moment before using the shortcut. Some apps expose selection data more slowly than others.

### Music is not ducking

Open **System Settings → Privacy & Security → Automation** and allow SuperSay to control the relevant music app.
