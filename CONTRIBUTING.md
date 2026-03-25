# Contributing

Thanks for helping improve AudioLocal.

## Development setup

1. Install Xcode 15 or newer.
2. Clone the repo.
3. Build the app:

```bash
swift build
./scripts/install_app.sh
```

4. If you want to test the local fallback, install Kokoro too:

```bash
./scripts/install_kokoro.sh
```

## Pull requests

- Keep changes focused.
- Include a short explanation of what changed and how you tested it.
- Update `README.md` if behavior or setup changed.
- If you change packaging or release behavior, test the corresponding script locally when possible.

## Release flow

- Standard CI runs on pushes and pull requests.
- Tagged releases use `.github/workflows/release.yml`.
- Create a tag like `v1.0.0` to publish GitHub release artifacts.

## Notes

- Gemini requires a user-supplied API key.
- Kokoro is optional and currently depends on a local Python environment.
- Intel builds are supported through the separate `x86_64` package artifacts.
