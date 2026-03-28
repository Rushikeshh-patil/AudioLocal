using AudioLocal.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace AudioLocal.Windows;

public sealed partial class MainWindow : Window
{
    private bool initialized;

    public MainWindow()
    {
        ViewModel = new MainWindowViewModel();
        InitializeComponent();
        RootGrid.DataContext = ViewModel;
        Activated += OnActivated;
    }

    public MainWindowViewModel ViewModel { get; }

    private async void OnActivated(object sender, WindowActivatedEventArgs args)
    {
        if (initialized)
        {
            return;
        }

        initialized = true;
        await ViewModel.InitializeAsync();
        GeminiApiKeyBox.Password = ViewModel.GetGeminiApiKey();
    }

    private async void OnImportEpubClick(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".epub");
        picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var file = await picker.PickSingleFileAsync();
        if (file is not null)
        {
            await ViewModel.ImportEpubAsync(file.Path);
        }
    }

    private void OnClearBookClick(object sender, RoutedEventArgs e) => ViewModel.ClearImportedBook();

    private async void OnGenerateCurrentClick(object sender, RoutedEventArgs e) => await ViewModel.GenerateCurrentAsync();

    private async void OnGenerateFullClick(object sender, RoutedEventArgs e) => await ViewModel.GenerateFullBookAsync();

    private void OnRevealLastFileClick(object sender, RoutedEventArgs e) => ViewModel.RevealLastFile();

    private void OnRevertSelectedChapterClick(object sender, RoutedEventArgs e) => ViewModel.RevertSelectedChapterText();

    private async void OnChooseFolderClick(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null)
        {
            ViewModel.ChooseCustomDirectory(folder.Path);
        }
    }

    private async void OnGeminiApiKeyChanged(object sender, RoutedEventArgs e) =>
        await ViewModel.SetGeminiApiKeyAsync(GeminiApiKeyBox.Password);
}
