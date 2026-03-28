using System.Diagnostics;
using System.Text;
using AudioLocal.Windows.Core.Models;

namespace AudioLocal.Windows.Core.Services;

public sealed class WindowsShareManager
{
    public async Task<string> EnsureManagedInboxAvailableAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        var inboxPath = settings.ManagedInboxPath;
        if (Directory.Exists(inboxPath))
        {
            Directory.CreateDirectory(inboxPath);
            return inboxPath;
        }

        TryOpenShareRoot(settings.ManagedShareRoot);
        var timeout = DateTimeOffset.UtcNow.AddSeconds(30);
        while (DateTimeOffset.UtcNow < timeout)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Directory.Exists(inboxPath))
            {
                Directory.CreateDirectory(inboxPath);
                return inboxPath;
            }

            try
            {
                Directory.CreateDirectory(inboxPath);
                return inboxPath;
            }
            catch
            {
                // Keep polling until the share is reachable.
            }

            await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken);
        }

        throw new IOException($"The managed inbox is unavailable at `{inboxPath}`.");
    }

    private static void TryOpenShareRoot(string shareRoot)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{shareRoot}\"",
                UseShellExecute = true
            });
        }
        catch
        {
            // Best effort only.
        }
    }
}

public sealed class WindowsAudioExporter
{
    public async Task ExportAsync(string destinationFilePath, SaveAudioRequest request, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destinationFilePath)!);

        if (request.Format == AudioExportFormat.Wav)
        {
            await File.WriteAllBytesAsync(destinationFilePath, request.WavData, cancellationToken);
            return;
        }

        var ffmpeg = ResolveFfmpegExecutable();
        var tempRoot = Path.Combine(Path.GetTempPath(), "AudioLocal-Export", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);

        try
        {
            var inputWavPath = Path.Combine(tempRoot, "input.wav");
            await File.WriteAllBytesAsync(inputWavPath, request.WavData, cancellationToken);

            if (request.Format == AudioExportFormat.M4a)
            {
                await RunProcessAsync(ffmpeg, $"-y -i \"{inputWavPath}\" -vn -c:a aac -b:a 64k \"{destinationFilePath}\"", cancellationToken);
                return;
            }

            var metadataPath = Path.Combine(tempRoot, "chapters.txt");
            await File.WriteAllTextAsync(
                metadataPath,
                BuildMetadata(request.Title, request.Author, request.ChapterMarkers),
                Encoding.UTF8,
                cancellationToken);

            var arguments = new StringBuilder();
            arguments.Append($"-y -i \"{inputWavPath}\" -i \"{metadataPath}\" ");
            if (request.CoverImageData is not null && request.CoverImageData.Length > 0)
            {
                var coverPath = Path.Combine(tempRoot, "cover" + GuessCoverExtension(request.CoverImageData));
                await File.WriteAllBytesAsync(coverPath, request.CoverImageData, cancellationToken);
                arguments.Append($"-i \"{coverPath}\" ");
            }

            arguments.Append("-map 0:a -c:a aac -b:a 64k -map_metadata 1 ");
            if (request.CoverImageData is not null && request.CoverImageData.Length > 0)
            {
                arguments.Append("-map 2:v -c:v copy -disposition:v attached_pic ");
            }

            arguments.Append($"\"{destinationFilePath}\"");
            await RunProcessAsync(ffmpeg, arguments.ToString(), cancellationToken);
        }
        finally
        {
            try
            {
                Directory.Delete(tempRoot, recursive: true);
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }
    }

    private static string BuildMetadata(string title, string? author, IReadOnlyList<ChapterMarker>? markers)
    {
        var builder = new StringBuilder();
        builder.AppendLine(";FFMETADATA1");
        builder.AppendLine($"title={EscapeMetadata(title)}");
        if (!string.IsNullOrWhiteSpace(author))
        {
            builder.AppendLine($"artist={EscapeMetadata(author)}");
        }

        if (markers is not null)
        {
            foreach (var marker in markers)
            {
                builder.AppendLine();
                builder.AppendLine("[CHAPTER]");
                builder.AppendLine("TIMEBASE=1/1000");
                builder.AppendLine($"START={marker.StartMilliseconds}");
                builder.AppendLine($"END={marker.EndMilliseconds}");
                builder.AppendLine($"title={EscapeMetadata(marker.Title)}");
            }
        }

        return builder.ToString();
    }

    private static string EscapeMetadata(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("=", "\\=", StringComparison.Ordinal)
            .Replace(";", "\\;", StringComparison.Ordinal)
            .Replace("#", "\\#", StringComparison.Ordinal)
            .Replace("\n", " ", StringComparison.Ordinal)
            .Replace("\r", " ", StringComparison.Ordinal);

    private static string ResolveFfmpegExecutable()
    {
        var env = Environment.GetEnvironmentVariable("AUDIOLOCAL_FFMPEG");
        if (!string.IsNullOrWhiteSpace(env) && File.Exists(env))
        {
            return env;
        }

        var bundled = Path.Combine(AppContext.BaseDirectory, "Tools", "ffmpeg", "ffmpeg.exe");
        if (File.Exists(bundled))
        {
            return bundled;
        }

        var pathEntries = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        foreach (var entry in pathEntries)
        {
            var candidate = Path.Combine(entry.Trim(), "ffmpeg.exe");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException("ffmpeg.exe was not found. Bundle it under Tools\\ffmpeg or set AUDIOLOCAL_FFMPEG.");
    }

    private static async Task RunProcessAsync(string fileName, string arguments, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Could not start `{fileName}`.");
        var stdOut = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stdErr = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"Audio export failed: {(await stdErr).Trim()}");
        }

        _ = await stdOut;
    }

    private static string GuessCoverExtension(byte[] data) =>
        data.Length >= 4 && data[0] == 0x89 && data[1] == 0x50 ? ".png" : ".jpg";
}

public sealed class WindowsStorageCoordinator
{
    private readonly WindowsAudioExporter exporter;
    private readonly WindowsShareManager shareManager;

    public WindowsStorageCoordinator(WindowsAudioExporter? exporter = null, WindowsShareManager? shareManager = null)
    {
        this.exporter = exporter ?? new WindowsAudioExporter();
        this.shareManager = shareManager ?? new WindowsShareManager();
    }

    public async Task<string> SaveAsync(
        SaveAudioRequest request,
        string itemName,
        AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        var baseDirectory = settings.SaveLocationMode switch
        {
            SaveLocationMode.ManagedInbox => await shareManager.EnsureManagedInboxAvailableAsync(settings, cancellationToken),
            _ => EnsureCustomDirectory(settings.CustomSaveDirectory)
        };

        var itemDirectory = Path.Combine(baseDirectory, itemName);
        Directory.CreateDirectory(itemDirectory);

        var destinationFilePath = Path.Combine(itemDirectory, $"{itemName}.{request.Format.FileExtension()}");
        await exporter.ExportAsync(destinationFilePath, request, cancellationToken);
        return destinationFilePath;
    }

    private static string EnsureCustomDirectory(string customPath)
    {
        if (string.IsNullOrWhiteSpace(customPath))
        {
            throw new InvalidOperationException("Choose a custom save folder before generating audio.");
        }

        Directory.CreateDirectory(customPath);
        return customPath;
    }
}
