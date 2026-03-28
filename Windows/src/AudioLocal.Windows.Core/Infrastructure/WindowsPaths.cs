namespace AudioLocal.Windows.Core.Infrastructure;

public static class WindowsPaths
{
    public static string AppDataRoot =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AudioLocal");

    public static string SettingsFilePath => Path.Combine(AppDataRoot, "settings.json");

    public static string SecretsRoot => Path.Combine(AppDataRoot, "secrets");

    public static string CacheRoot => Path.Combine(AppDataRoot, "cache");

    public static string LogsRoot => Path.Combine(AppDataRoot, "logs");

    public static string RuntimeStateRoot => Path.Combine(AppDataRoot, "runtime");

    public static void EnsureAppFolders()
    {
        Directory.CreateDirectory(AppDataRoot);
        Directory.CreateDirectory(SecretsRoot);
        Directory.CreateDirectory(CacheRoot);
        Directory.CreateDirectory(LogsRoot);
        Directory.CreateDirectory(RuntimeStateRoot);
    }
}
