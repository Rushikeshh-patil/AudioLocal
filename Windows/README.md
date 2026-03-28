# AudioLocal for Windows

This folder contains the Windows-native implementation of AudioLocal.

## Projects

- `src/AudioLocal.Windows`
  WinUI 3 desktop application for Windows.
- `src/AudioLocal.Windows.Core`
  Shared Windows services for EPUB import, Kokoro runtime selection, WAV stitching, ffmpeg export, DPAPI secret storage, and save-target coordination.
- `tests/AudioLocal.Windows.Core.Tests`
  xUnit coverage for EPUB import heuristics and GPU backend ordering.

## Build

From the repo root:

```powershell
dotnet build .\Windows\AudioLocal.Windows.slnx
dotnet test .\Windows\tests\AudioLocal.Windows.Core.Tests\AudioLocal.Windows.Core.Tests.csproj
```

## Release Packaging

From the repo root:

```powershell
.\Windows\scripts\package_release.ps1 -Version 1.1.0 -Architecture x64
```

This produces these release assets in `dist\`:

- `AudioLocal-Windows-x64-<version>.zip`
- `AudioLocal-Windows-x64-<version>.msi`
- matching `.sha256` files

Optional bundling hooks:

- `AUDIOLOCAL_WINDOWS_RUNTIME_ROOT`
  Root folder containing `KokoroCuda`, `KokoroDirectML`, and/or `KokoroCpu` to compress into the installer payload as runtime archives.
- `AUDIOLOCAL_WINDOWS_FFMPEG_PATH`
  Full path to `ffmpeg.exe` to bundle under `Tools\ffmpeg\ffmpeg.exe` in the release payload.

## Runtime model

Windows uses Kokoro only for local synthesis.

Backend selection order:

1. `CUDA` when a healthy NVIDIA adapter is detected.
2. `DirectML` for other hardware GPUs.
3. `CPU` as the final fallback.

The app remembers the last known-good local backend and tries that first on the next run.

## Kokoro runtime hooks

The WinUI app launches `Runtime\kokoro_windows.py` and looks for Python runtimes in either bundled runtime folders or these environment variables:

- `AUDIOLOCAL_KOKORO_CUDA_PYTHON`
- `AUDIOLOCAL_KOKORO_DIRECTML_PYTHON`
- `AUDIOLOCAL_KOKORO_CPU_PYTHON`

Bundled runtime archive names expected under the app output:

- `RuntimeArchives\KokoroCuda.zip`
- `RuntimeArchives\KokoroDirectML.zip`
- `RuntimeArchives\KokoroCpu.zip`

On first use, the app expands those archives into `%LOCALAPPDATA%\AudioLocal\Runtimes\...` and launches Python from there.

## Audio export

Windows export paths support:

- `.wav`
- `.m4a`
- `.m4b`

`WindowsAudioExporter` looks for `ffmpeg.exe` via `AUDIOLOCAL_FFMPEG`, then `Tools\ffmpeg\ffmpeg.exe`, then `PATH`. Full-book exports preserve chapter markers and optional cover art when creating `.m4b`.
