using System.Text.Json.Serialization;

namespace AudioLocal.Windows.Core.Models;

public enum ProviderMode
{
    LocalOnly,
    Automatic,
    GeminiOnly
}

public enum SaveLocationMode
{
    ManagedInbox,
    CustomFolder
}

public enum AccelerationMode
{
    Auto,
    Cuda,
    DirectML,
    Cpu
}

public enum ResolvedLocalBackend
{
    Cuda,
    DirectML,
    Cpu
}

public sealed class AppSettings
{
    public const string DefaultGeminiModel = "gemini-2.5-flash-preview-tts";
    public const string DefaultGeminiVoice = "Kore";
    public const string DefaultKokoroVoice = "af_heart";
    public const string DefaultManagedShareRoot = @"\\100.73.8.90\privateserver";
    public const string DefaultManagedInboxPath = @"\\100.73.8.90\privateserver\ubuntu\my-audio-cloud\library\articles\Inbox";

    public ProviderMode ProviderMode { get; set; } = ProviderMode.LocalOnly;
    public AccelerationMode AccelerationMode { get; set; } = AccelerationMode.Auto;
    public SaveLocationMode SaveLocationMode { get; set; } = SaveLocationMode.ManagedInbox;
    public AudioExportFormat ExportFormat { get; set; } = AudioExportFormat.M4b;
    public string DraftTitle { get; set; } = string.Empty;
    public string DraftBody { get; set; } = string.Empty;
    public string KokoroVoice { get; set; } = DefaultKokoroVoice;
    public double KokoroSpeed { get; set; } = 1.0;
    public string GeminiModel { get; set; } = DefaultGeminiModel;
    public string GeminiVoice { get; set; } = DefaultGeminiVoice;
    public string CustomSaveDirectory { get; set; } = string.Empty;
    public string ManagedShareRoot { get; set; } = DefaultManagedShareRoot;
    public string ManagedInboxPath { get; set; } = DefaultManagedInboxPath;
    public string LastSavedPath { get; set; } = string.Empty;
    public string LastBackendLabel { get; set; } = string.Empty;
    public string LastDeviceLabel { get; set; } = string.Empty;

    [JsonConverter(typeof(JsonStringEnumConverter<ResolvedLocalBackend>))]
    public ResolvedLocalBackend? LastKnownGoodBackend { get; set; }
}
