# Changelog

## 1.0.3 - 2026-03-25

- Fixed `WAV` export when saving locally or to a custom folder
- Added a visible Kokoro device badge in the main header so GPU usage is easier to confirm
- Added a generation progress bar with estimated remaining time for synthesis and save phases

## 1.0.2 - 2026-03-25

- Added selectable export formats: `M4B`, `M4A`, and `WAV`
- Updated GitHub Actions workflows to Node 24-based action versions

## 1.0.1 - 2026-03-25

- Bundled Kokoro runtime and prefetched model cache in packaged downloads
- Kokoro-first local generation by default with Gemini optional
- Self-contained Apple Silicon and Intel release packaging for Kokoro
- CI bundle build skips bundled Kokoro to keep smoke builds lighter

## 1.0.0 - 2026-03-25

Initial public release.

- Native SwiftUI macOS app for turning pasted text into speech
- Gemini and Kokoro generation modes
- Gemini and Kokoro voice pickers
- Local staging plus AAC `.m4b` export
- Audiobookshelf Inbox save mode with SMB auto-mount
- Custom folder save mode
- Apple Silicon and Intel release packaging
- GitHub Actions workflows for CI and tagged releases
