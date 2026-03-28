namespace AudioLocal.Windows.Core.Models;

public sealed record SynthesisRequest(
    string Text,
    string Voice,
    double Speed,
    AccelerationMode AccelerationMode,
    ResolvedLocalBackend? LastKnownGoodBackend);

public sealed record KokoroSynthesisResult(
    byte[] AudioData,
    ResolvedLocalBackend Backend,
    string DeviceLabel,
    string BackendLabel);

public sealed record ChapterWavSegment(string Title, byte[] WavData);

public sealed record ChapterMarker(string Title, int StartMilliseconds, int EndMilliseconds);

public sealed record StitchedAudio(byte[] WavData, IReadOnlyList<ChapterMarker> ChapterMarkers);

public sealed record SaveAudioRequest(
    byte[] WavData,
    string ItemName,
    AudioExportFormat Format,
    string Title,
    string? Author,
    IReadOnlyList<ChapterMarker>? ChapterMarkers = null,
    byte[]? CoverImageData = null);
