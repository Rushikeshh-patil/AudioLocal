namespace AudioLocal.Windows.Core.Models;

public enum AudioExportFormat
{
    M4b,
    M4a,
    Wav
}

public static class AudioExportFormatExtensions
{
    public static string Title(this AudioExportFormat format) => format switch
    {
        AudioExportFormat.M4b => "M4B audiobook",
        AudioExportFormat.M4a => "M4A audio",
        _ => "WAV"
    };

    public static string FileExtension(this AudioExportFormat format) => format switch
    {
        AudioExportFormat.M4b => "m4b",
        AudioExportFormat.M4a => "m4a",
        _ => "wav"
    };

    public static string ProcessingDescription(this AudioExportFormat format) => format switch
    {
        AudioExportFormat.M4b => "compressed to AAC `.m4b`",
        AudioExportFormat.M4a => "compressed to AAC `.m4a`",
        _ => "kept as uncompressed `.wav`"
    };
}
