using System.Text.Json;
using System.Text.Json.Serialization;
using AudioLocal.Windows.Core.Infrastructure;
using AudioLocal.Windows.Core.Models;

namespace AudioLocal.Windows.Core.Services;

public interface IAppSettingsStore
{
    Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default);
}

public sealed class JsonAppSettingsStore : IAppSettingsStore
{
    private static readonly SemaphoreSlim FileGate = new(1, 1);
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public async Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        await FileGate.WaitAsync(cancellationToken);
        try
        {
        WindowsPaths.EnsureAppFolders();
        if (!File.Exists(WindowsPaths.SettingsFilePath))
        {
            return new AppSettings();
        }

        await using var stream = new FileStream(
            WindowsPaths.SettingsFilePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite);
        var settings = await JsonSerializer.DeserializeAsync<AppSettings>(stream, SerializerOptions, cancellationToken);
        return settings ?? new AppSettings();
        }
        finally
        {
            FileGate.Release();
        }
    }

    public async Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(settings);
        await FileGate.WaitAsync(cancellationToken);
        try
        {
        WindowsPaths.EnsureAppFolders();

        var tempFilePath = $"{WindowsPaths.SettingsFilePath}.tmp";
        await using (var stream = new FileStream(
            tempFilePath,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None))
        {
            await JsonSerializer.SerializeAsync(stream, settings, SerializerOptions, cancellationToken);
            await stream.FlushAsync(cancellationToken);
        }

        if (File.Exists(WindowsPaths.SettingsFilePath))
        {
            File.Replace(tempFilePath, WindowsPaths.SettingsFilePath, destinationBackupFileName: null, ignoreMetadataErrors: true);
        }
        else
        {
            File.Move(tempFilePath, WindowsPaths.SettingsFilePath);
        }
        }
        finally
        {
            FileGate.Release();
        }
    }
}
