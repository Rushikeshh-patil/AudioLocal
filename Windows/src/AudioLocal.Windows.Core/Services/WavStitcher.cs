using AudioLocal.Windows.Core.Models;

namespace AudioLocal.Windows.Core.Services;

public sealed class WavStitcher
{
    public StitchedAudio Stitch(IReadOnlyList<ChapterWavSegment> chapters, double pauseBetweenChaptersSeconds = 0.85)
    {
        if (chapters.Count == 0)
        {
            throw new InvalidOperationException("No chapter audio was generated.");
        }

        var parsed = chapters.Select(static chapter => (chapter.Title, Segment: ParseWav(chapter.WavData))).ToArray();
        var first = parsed[0].Segment;

        if (parsed.Any(segment => segment.Segment.Format != first.Format))
        {
            throw new InvalidOperationException("The generated chapter audio uses mismatched WAV formats.");
        }

        var silenceFrameCount = (int)Math.Round(first.Format.SampleRate * pauseBetweenChaptersSeconds, MidpointRounding.AwayFromZero);
        var silenceByteCount = silenceFrameCount * first.Format.BlockAlign;
        var silence = new byte[Math.Max(0, silenceByteCount)];

        var markers = new List<ChapterMarker>(parsed.Length);
        using var pcmBuffer = new MemoryStream();
        var cursorMs = 0;

        for (var index = 0; index < parsed.Length; index++)
        {
            var (title, segment) = parsed[index];
            var durationMs = segment.DurationMilliseconds();
            markers.Add(new ChapterMarker(title, cursorMs, cursorMs + durationMs));
            pcmBuffer.Write(segment.PcmData);

            cursorMs += durationMs;
            if (index < parsed.Length - 1 && silence.Length > 0)
            {
                pcmBuffer.Write(silence);
                cursorMs += (int)Math.Round(pauseBetweenChaptersSeconds * 1000, MidpointRounding.AwayFromZero);
            }
        }

        return new StitchedAudio(
            WavEncoder.MakeWav(pcmBuffer.ToArray(), first.Format.SampleRate, first.Format.Channels, first.Format.BitsPerSample),
            markers);
    }

    private static ParsedWav ParseWav(byte[] data)
    {
        if (data.Length < 44 ||
            data[0] != (byte)'R' || data[1] != (byte)'I' || data[2] != (byte)'F' || data[3] != (byte)'F' ||
            data[8] != (byte)'W' || data[9] != (byte)'A' || data[10] != (byte)'V' || data[11] != (byte)'E')
        {
            throw new InvalidOperationException("The generated chapter audio is not PCM WAV.");
        }

        var offset = 12;
        WavFormat? format = null;
        byte[]? pcmData = null;

        while (offset + 8 <= data.Length)
        {
            var chunkId = System.Text.Encoding.ASCII.GetString(data, offset, 4);
            var chunkSize = BitConverter.ToInt32(data, offset + 4);
            var chunkStart = offset + 8;
            var nextChunkOffset = chunkStart + chunkSize + (chunkSize % 2);

            if (nextChunkOffset > data.Length)
            {
                throw new InvalidOperationException("The generated chapter audio is malformed.");
            }

            if (chunkId == "fmt ")
            {
                var audioFormat = BitConverter.ToInt16(data, chunkStart);
                var channels = BitConverter.ToInt16(data, chunkStart + 2);
                var sampleRate = BitConverter.ToInt32(data, chunkStart + 4);
                var blockAlign = BitConverter.ToInt16(data, chunkStart + 12);
                var bitsPerSample = BitConverter.ToInt16(data, chunkStart + 14);

                if (audioFormat != 1 || bitsPerSample != 16)
                {
                    throw new InvalidOperationException("The generated chapter audio must be 16-bit PCM WAV.");
                }

                format = new WavFormat(sampleRate, channels, bitsPerSample, blockAlign);
            }
            else if (chunkId == "data")
            {
                pcmData = data.Skip(chunkStart).Take(chunkSize).ToArray();
            }

            offset = nextChunkOffset;
        }

        if (format is null || pcmData is null)
        {
            throw new InvalidOperationException("The generated chapter audio could not be stitched.");
        }

        return new ParsedWav(format, pcmData);
    }

    private sealed record ParsedWav(WavFormat Format, byte[] PcmData)
    {
        public int DurationMilliseconds() =>
            (int)Math.Round((double)PcmData.Length / Format.BlockAlign / Format.SampleRate * 1000, MidpointRounding.AwayFromZero);
    }

    private sealed record WavFormat(int SampleRate, short Channels, short BitsPerSample, short BlockAlign);
}
