namespace AudioLocal.Windows.Core.Services;

public static class WavEncoder
{
    public static byte[] WrapIfNeeded(byte[] audioData, string mimeType)
    {
        if (audioData.Length >= 4 &&
            audioData[0] == (byte)'R' &&
            audioData[1] == (byte)'I' &&
            audioData[2] == (byte)'F' &&
            audioData[3] == (byte)'F')
        {
            return audioData;
        }

        if (!mimeType.Contains("audio", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Unsupported audio payload: {mimeType}");
        }

        var sampleRate = ParseIntegerParameter(mimeType, "rate") ?? 24_000;
        var channels = ParseIntegerParameter(mimeType, "channels") ?? 1;
        return MakeWav(audioData, sampleRate, channels, bitsPerSample: 16);
    }

    public static byte[] MakeWav(byte[] pcmData, int sampleRate, int channels, int bitsPerSample)
    {
        var byteRate = sampleRate * channels * bitsPerSample / 8;
        var blockAlign = channels * bitsPerSample / 8;
        var chunkSize = 36 + pcmData.Length;

        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);
        writer.Write("RIFF"u8.ToArray());
        writer.Write(chunkSize);
        writer.Write("WAVE"u8.ToArray());
        writer.Write("fmt "u8.ToArray());
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)channels);
        writer.Write(sampleRate);
        writer.Write(byteRate);
        writer.Write((short)blockAlign);
        writer.Write((short)bitsPerSample);
        writer.Write("data"u8.ToArray());
        writer.Write(pcmData.Length);
        writer.Write(pcmData);
        writer.Flush();
        return stream.ToArray();
    }

    private static int? ParseIntegerParameter(string mimeType, string name)
    {
        foreach (var part in mimeType.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = part.Trim();
            if (trimmed.StartsWith($"{name}=", StringComparison.OrdinalIgnoreCase) &&
                int.TryParse(trimmed[(name.Length + 1)..], out var value))
            {
                return value;
            }
        }

        return null;
    }
}
