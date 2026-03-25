# AudioLocal

Lightweight native macOS app for turning pasted article text into compressed `.m4b` audiobook files.

By default it saves to:

`/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox`

but you can also switch the app to save into any custom folder from the UI.

Each generated item is written into its own folder, for example:

`/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox/my-article-20260311-154500/my-article-20260311-154500.m4b`

If the default SMB volume is not mounted, the app tries to open `smb://100.73.8.90/privateserver`, waits for the share to appear in `/Volumes`, and then saves the file.

## Features

- Native SwiftUI macOS UI
- Title + article text input
- Gemini TTS via the Gemini API
- Automatic fallback to Kokoro when Gemini quota is exhausted
- Switchable save target: Audiobookshelf Inbox or any custom folder
- Saves the final file as AAC `.m4b`
- Reveals the generated file in Finder
- Buildable into a normal `.app`, `.zip`, and `.dmg` for GitHub releases

## Build and run

Open the package in Xcode or run:

```bash
swift build
swift run AudioLocal
```

`swift run AudioLocal` launches the raw executable, which can emit harmless AppKit warnings because it is not a full `.app` bundle.

For a normal installed macOS app with a bundle identifier, use:

```bash
./scripts/install_app.sh
open /Applications/AudioLocal.app
```

## Save locations

AudioLocal supports two save modes:

- `Audiobookshelf Inbox`: saves to `/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox` and will try to mount `smb://100.73.8.90/privateserver` if that share is not mounted yet.
- `Custom folder`: lets you choose any local or already-mounted folder from the UI. Each export is still placed in its own subfolder:

`/chosen/path/my-article-20260325-141500/my-article-20260325-141500.m4b`

The app stages the audio locally first, compresses it to AAC `.m4b`, and only then copies the final file to the destination. That keeps the UI responsive even when the final location is on a slow network share.

## Gemini setup

Enter your Gemini API key in the app. The default model is `gemini-2.5-flash-preview-tts`, which matches Google's Gemini TTS documentation as of March 11, 2026.

Official docs used for the implementation:

- [Gemini TTS docs](https://ai.google.dev/gemini-api/docs/speech-generation)

## Kokoro setup

The Kokoro fallback uses the official Python package through a bundled helper script. Create a local Python environment and install the dependencies with:

```bash
./scripts/install_kokoro.sh
```

The installer automatically prefers Python 3.12 / 3.11 / 3.10 and will fail fast if only Python 3.9 or older is available.

Then set the Kokoro Python path inside the app to:

`/Users/rushikeshpatil/dev/audio_local/.venv-kokoro/bin/python3`

The first Kokoro run downloads the model weights and English language assets, so expect an initial one-time download.

On Apple Silicon, the Kokoro helper now prefers the Apple GPU through PyTorch `mps` automatically and falls back to CPU if a required operation is unsupported.

If Kokoro needs phoneme support on your machine, install `espeak-ng`:

```bash
brew install espeak-ng
```

Official reference used for the helper:

- [Kokoro README](https://github.com/hexgrad/kokoro)

## Packaging and GitHub releases

To build a distributable app bundle locally:

```bash
./scripts/build_app_bundle.sh
```

That builds the host architecture by default. You can also target a specific architecture:

```bash
./scripts/build_app_bundle.sh 1.0.0 1 arm64
./scripts/build_app_bundle.sh 1.0.0 1 x86_64
```

To create release artifacts for GitHub:

```bash
./scripts/package_release.sh 1.0.0 1 arm64
./scripts/package_release.sh 1.0.0 1 x86_64
```

That produces:

- `dist/build/apple-silicon/AudioLocal.app`
- `dist/build/intel/AudioLocal.app`
- `dist/AudioLocal-macOS-apple-silicon-1.0.0.zip`
- `dist/AudioLocal-macOS-intel-1.0.0.zip`
- `dist/AudioLocal-macOS-apple-silicon-1.0.0.dmg`
- `dist/AudioLocal-macOS-intel-1.0.0.dmg`
- matching `.sha256` checksum files

The included GitHub Actions workflow at `.github/workflows/release.yml` now builds both Apple Silicon and Intel artifacts automatically on `v*` tags and attaches them to the GitHub release.

## Open-source notes

The repository now includes an `MIT` license in `LICENSE`.

Two things are still important before publishing publicly:

- The downloadable app works as a normal macOS app for Gemini, but Kokoro is not fully self-contained yet. Users still need the local Kokoro Python runtime from `./scripts/install_kokoro.sh` if they want offline fallback.
- Intel Macs are supported by the separate Intel build, but Kokoro runs on CPU there because Apple `mps` acceleration is Apple Silicon only.

Also note that GitHub release builds are not notarized yet. macOS users will likely need to right-click the app and choose `Open` the first time unless you later add Apple Developer ID signing and notarization.
