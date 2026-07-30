# SuperSay (archived legacy release)

> ## SuperSay is retired. Voqora is the current product.
>
> SuperSay remains available as its final, archived `v2.0.3` release. It receives no future features or development. For the supported product experience, download [Voqora](https://github.com/himudigonda/Voqora/releases/latest).

SuperSay is an earlier public native macOS text-to-speech product built by Himansh Mudigonda. It turns selected text into local speech and can create audiobooks from supported documents. This repository preserves the final legacy release for people who already use it and for anyone who wants to inspect the source.

## Move to Voqora

1. Download and install [Voqora](https://github.com/himudigonda/Voqora/releases/latest).
2. Open Voqora. If SuperSay is present in `/Applications` or `~/Applications`, Voqora offers to import compatible playback and appearance preferences.
3. Confirm that Voqora works for you, then move SuperSay to Trash when you are ready. Neither app removes the other automatically.

SuperSay does not check a legacy update channel. Its in-app **Update to Voqora**
action verifies the official Voqora DMG from GitHub, then opens it in Finder for
an explicit drag to Applications. It also links directly to the current
[Voqora release](https://github.com/himudigonda/Voqora/releases/latest),
[Voqora project](https://github.com/himudigonda/Voqora), and
[Voqora product story](https://himudigonda.me/blog/voqora).

SuperSay and Voqora report separate anonymous installation counts. They are not presented as a deduplicated people count unless a user deliberately provides a legitimate shared identity.

## What this final release does

- Adds an always-visible in-app notice pointing to Voqora.
- Removes the obsolete SuperSay account and sign-in screens.
- Sends optional counts-only telemetry to the active Voqora endpoint with `product: "supersay"`, so the legacy population remains distinct.
- Keeps SuperSay's existing local TTS and audiobook capabilities intact.

It does **not** include Voqora features or any private successor work.

## Install the archived app

1. Download the `SuperSay-2.0.3.dmg` asset from the final release.
2. Drag `SuperSay.app` to `/Applications`.
3. If macOS still blocks this archived build after choosing **Open** from the contextual menu, run this scoped command:

```bash
xattr -cr /Applications/SuperSay.app
```

This affects only that app bundle. It removes the download quarantine attribute; it does not change Gatekeeper system-wide or grant SuperSay additional permissions.

## What remains local, and what can leave the Mac

Text-to-speech inference runs in the bundled local backend. The optional Gemini-assisted audiobook cleanup sends document text to Google only when you supply a Gemini API key and choose that flow. Optional telemetry sends only an anonymous installation ID, version, event name, and whitelisted aggregate fields such as character count or generated audio duration. It never sends spoken text, filenames, audio, email, credentials, or API keys.

See [PRIVACY.md](./PRIVACY.md) for the final release's exact network contract.

## Development and licence

This repository is archived after `v2.0.3`; pull requests and new feature requests are not accepted. The final source remains available under the [MIT License](./LICENSE). Existing releases remain governed by the licences distributed with those releases.

For the active codebase, releases, and issues, use [Voqora](https://github.com/himudigonda/Voqora).
