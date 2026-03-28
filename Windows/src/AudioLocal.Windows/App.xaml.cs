using Microsoft.UI.Xaml;
using System.Text;

namespace AudioLocal.Windows;

public partial class App : Application
{
    private Window? window;

    public App()
    {
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnCurrentDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            Log("Launching AudioLocal.Windows.");
            window = new MainWindow();
            window.Activate();
            Log("Main window activated.");
        }
        catch (Exception exception)
        {
            Log($"Launch failure: {exception}");
            throw;
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs args)
    {
        Log($"Microsoft.UI.Xaml.UnhandledException: {args.Exception}");
    }

    private void OnCurrentDomainUnhandledException(object sender, System.UnhandledExceptionEventArgs args)
    {
        Log($"AppDomain.CurrentDomain.UnhandledException: {args.ExceptionObject}");
    }

    private void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs args)
    {
        Log($"TaskScheduler.UnobservedTaskException: {args.Exception}");
    }

    private static void Log(string message)
    {
        try
        {
            var logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "AudioLocal",
                "logs");
            Directory.CreateDirectory(logDirectory);
            var logPath = Path.Combine(logDirectory, "windows-startup.log");
            File.AppendAllText(
                logPath,
                $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}",
                Encoding.UTF8);
        }
        catch
        {
            // Logging should never block app startup.
        }
    }
}
