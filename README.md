# AudioLocal

Lightweight native macOS app for turning pasted article text into audiobook or audio files.

By default it saves to:

`/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox`

but you can also switch the app to save into any custom folder from the UI.

Each generated item is written into its own folder, for example:

`/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox/my-article-20260311-154500/my-article-20260311-154500.m4b`

If the default SMB volume is not mounted, the app tries to open `smb://100.73.8.90/privateserver`, waits for the share to appear in `/Volumes`, and then saves the file.

## Features

- Native SwiftUI macOS UI
- Title + article text input
- Selectable local TTS engines: Kokoro or Voxtral MLX
- Gemini TTS via the Gemini API
- Gemini is optional instead of required
- Switchable save target: Audiobookshelf Inbox or any custom folder
- Choose the final export format: `.m4b`, `.m4a`, or `.wav`
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

`install_app.sh` now bundles the Kokoro runtime and prefetched model cache into the app so the installed `.app` can run locally without asking end users to install Python, Torch, or Kokoro separately.

On Apple Silicon, `install_app.sh` also bundles the Voxtral MLX runtime by default, but not the Voxtral model weights. Those are downloaded separately into a user cache outside the app bundle.

## Save locations

AudioLocal supports two save modes:

- `Audiobookshelf Inbox`: saves to `/Volumes/privateserver/ubuntu/my-audio-cloud/library/articles/Inbox` and will try to mount `smb://100.73.8.90/privateserver` if that share is not mounted yet.
- `Custom folder`: lets you choose any local or already-mounted folder from the UI. Each export is still placed in its own subfolder:

`/chosen/path/my-article-20260325-141500/my-article-20260325-141500.m4b`

The app stages the audio locally first, exports it in the selected format, and only then copies the final file to the destination. That keeps the UI responsive even when the final location is on a slow network share.

## Default runtime

AudioLocal now defaults to `Local only`, with `Kokoro` selected as the default local model.

- Kokoro is bundled into the packaged app and works offline by default.
- Voxtral MLX is optional and available on Apple Silicon builds.
- The Voxtral model weights are kept separate from the installer and are downloaded into a user cache when needed.
- Gemini is optional. Users only need to enter a Gemini API key if they want to switch to `Gemini only` or `Automatic`.

The packaged app includes:

- a bundled Python runtime
- the Kokoro Python packages
- the prefetched `hexgrad/Kokoro-82M` model cache
- on Apple Silicon, the MLX Voxtral Python packages

That makes the GitHub downloads significantly larger, but it keeps installation to a normal drag-and-drop app install.

## Gemini setup

Enter your Gemini API key in the app. The default model is `gemini-2.5-flash-preview-tts`, which matches Google's Gemini TTS documentation as of March 11, 2026.

Official docs used for the implementation:

- [Gemini TTS docs](https://ai.google.dev/gemini-api/docs/speech-generation)

## Kokoro setup

The Kokoro fallback uses the official Python package through a bundled helper script. Create a local Python environment and install the dependencies with:

```bash
./scripts/install_kokoro.sh
```

The installer automatically prefers Python 3.12 / 3.11 / 3.10 and will fail fast if only Python 3.9 or older is available. It also prefetched the Kokoro model into `.kokoro-cache/huggingface` so release builds can bundle it.

For local development, the Kokoro Python path is:

`/Users/rushikeshpatil/dev/audio_local/.venv-kokoro/bin/python3`

On Apple Silicon, the Kokoro helper now prefers the Apple GPU through PyTorch `mps` automatically and falls back to CPU if a required operation is unsupported.

Official reference used for the helper:

- [Kokoro README](https://github.com/hexgrad/kokoro)

## Voxtral MLX setup

Voxtral MLX is an optional local model for Apple Silicon Macs. Create its local Python environment with:

```bash
./scripts/install_voxtral_mlx.sh
```

The runtime installer currently pulls `mlx-audio` from GitHub rather than PyPI because Voxtral support is still moving quickly.

The installer also pulls `tiktoken`, which Voxtral currently needs for its Tekken tokenizer.

Download the model separately with:

```bash
./scripts/pull_voxtral_mlx_model.sh
```

For local development, the Voxtral Python path is:

`/Users/rushikeshpatil/dev/audio_local/.venv-voxtral/bin/python3`

The default model ID in the app is:

`mlx-community/Voxtral-4B-TTS-2603-mlx-bf16`

The model download script stores Voxtral in:

`~/Library/Application Support/AudioLocal/VoxtralModels/huggingface`

That keeps the app installer lightweight while still letting the installed app reuse the same shared model cache.

As of March 27, 2026, local Voxtral MLX works on this project when the runtime is refreshed from the current `mlx-audio` GitHub build. Some older installs still report `mlx-audio 0.4.1` while missing the `voxtral_tts` loader, so re-run `./scripts/install_voxtral_mlx.sh` if the app reports a runtime mismatch.

The linked bf16 model fits on Apple Silicon machines like this `24 GB` M4 Mac, but it is still slow. The MLX model card lists the bf16 variant at about `~8 GB` and roughly `6.50x` short-form real-time factor on Apple Silicon, so it is better suited to offline narration than quick interactive playback.

References used for the helper:

- [mlx-audio](https://github.com/Blaizzy/mlx-audio)
- [Voxtral 4B TTS model card](https://huggingface.co/mistralai/Voxtral-4B-TTS-2603)
- [MLX Voxtral model card](https://huggingface.co/mlx-community/Voxtral-4B-TTS-2603-mlx-bf16)

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

The included GitHub Actions workflow at `.github/workflows/release.yml` now installs Kokoro, can bundle Voxtral MLX for Apple Silicon builds, builds both Apple Silicon and Intel artifacts automatically on `v*` tags, and attaches them to the GitHub release.

## Open-source notes

The repository now includes an `MIT` license in `LICENSE`.

One thing is still important before publishing publicly:

- Intel Macs are supported by the separate Intel build, but Kokoro runs on CPU there because Apple `mps` acceleration is Apple Silicon only.
- Voxtral MLX is Apple Silicon only and uses the `CC BY-NC 4.0` license inherited from the released voice references.

Also note that GitHub release builds are not notarized yet. macOS users will likely need to right-click the app and choose `Open` the first time unless you later add Apple Developer ID signing and notarization.
