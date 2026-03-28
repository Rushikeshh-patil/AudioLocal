using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using AudioLocal.Windows.Core.Infrastructure;
using AudioLocal.Windows.Core.Models;
using AudioLocal.Windows.Core.Services;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Xaml;

namespace AudioLocal.Windows.ViewModels;

public partial class MainWindowViewModel : ObservableObject
{
    private readonly IAppSettingsStore settingsStore;
    private readonly ISecretStore secretStore;
    private readonly EpubImportService epubImportService;
    private readonly KokoroSynthesizer kokoroSynthesizer;
    private readonly GeminiTtsClient geminiTtsClient;
    private readonly WindowsStorageCoordinator storageCoordinator;
    private readonly WavStitcher wavStitcher;

    private ImportedBook? importedBook;
    private ResolvedLocalBackend? lastKnownGoodBackend;
    private bool suppressPersistence;
    private string geminiApiKey = string.Empty;
    private CancellationTokenSource? generationTelemetryCts;
    private DateTimeOffset? generationStartedAt;
    private string generationElapsedText = string.Empty;
    private string progressDetailBase = string.Empty;
    private string generationSourceInfo = "Source: waiting for a conversion";
    private string generationRequestInfo = string.Empty;
    private string generationOutputInfo = string.Empty;
    private string generationBackendPlanInfo = "Backend plan: idle";
    private string generationRuntimeInfo = "Runtime: idle";
    private string generationWorkerInfo = "Worker: idle";
    private string generationScratchInfo = string.Empty;
    private readonly List<string> generationEvents = [];

    public MainWindowViewModel(
        IAppSettingsStore? settingsStore = null,
        ISecretStore? secretStore = null,
        EpubImportService? epubImportService = null,
        KokoroSynthesizer? kokoroSynthesizer = null,
        GeminiTtsClient? geminiTtsClient = null,
        WindowsStorageCoordinator? storageCoordinator = null,
        WavStitcher? wavStitcher = null)
    {
        this.settingsStore = settingsStore ?? new JsonAppSettingsStore();
        this.secretStore = secretStore ?? new DpapiSecretStore();
        this.epubImportService = epubImportService ?? new EpubImportService();
        this.kokoroSynthesizer = kokoroSynthesizer ?? new KokoroSynthesizer();
        this.geminiTtsClient = geminiTtsClient ?? new GeminiTtsClient();
        this.storageCoordinator = storageCoordinator ?? new WindowsStorageCoordinator();
        this.wavStitcher = wavStitcher ?? new WavStitcher();

        ProviderOptions =
        [
            new ChoiceOption<ProviderMode>(ProviderMode.LocalOnly, "Local only"),
            new ChoiceOption<ProviderMode>(ProviderMode.Automatic, "Automatic"),
            new ChoiceOption<ProviderMode>(ProviderMode.GeminiOnly, "Gemini only")
        ];

        AccelerationOptions =
        [
            new ChoiceOption<AccelerationMode>(AccelerationMode.Auto, "Auto"),
            new ChoiceOption<AccelerationMode>(AccelerationMode.Cuda, "CUDA"),
            new ChoiceOption<AccelerationMode>(AccelerationMode.DirectML, "DirectML"),
            new ChoiceOption<AccelerationMode>(AccelerationMode.Cpu, "CPU")
        ];

        SaveLocationOptions =
        [
            new ChoiceOption<SaveLocationMode>(SaveLocationMode.ManagedInbox, "Audiobookshelf Inbox"),
            new ChoiceOption<SaveLocationMode>(SaveLocationMode.CustomFolder, "Custom folder")
        ];

        ExportFormatOptions =
        [
            new ChoiceOption<AudioExportFormat>(AudioExportFormat.M4b, AudioExportFormat.M4b.Title()),
            new ChoiceOption<AudioExportFormat>(AudioExportFormat.M4a, AudioExportFormat.M4a.Title()),
            new ChoiceOption<AudioExportFormat>(AudioExportFormat.Wav, AudioExportFormat.Wav.Title())
        ];

        KokoroVoices = KokoroVoiceCatalog.All;
        GeminiVoices = GeminiVoiceCatalog.All;
        ImportedChapters.CollectionChanged += (_, _) => RaiseComputedPropertyChanges();
    }

    public ObservableCollection<ImportedChapterItemViewModel> ImportedChapters { get; } = [];

    public IReadOnlyList<ChoiceOption<ProviderMode>> ProviderOptions { get; }

    public IReadOnlyList<ChoiceOption<AccelerationMode>> AccelerationOptions { get; }

    public IReadOnlyList<ChoiceOption<SaveLocationMode>> SaveLocationOptions { get; }

    public IReadOnlyList<ChoiceOption<AudioExportFormat>> ExportFormatOptions { get; }

    public IReadOnlyList<VoiceOption> KokoroVoices { get; }

    public IReadOnlyList<VoiceOption> GeminiVoices { get; }

    [ObservableProperty]
    private string articleTitle = string.Empty;

    [ObservableProperty]
    private string articleBody = string.Empty;

    [ObservableProperty]
    private ProviderMode selectedProviderMode = ProviderMode.LocalOnly;

    [ObservableProperty]
    private AccelerationMode selectedAccelerationMode = AccelerationMode.Auto;

    [ObservableProperty]
    private SaveLocationMode selectedSaveLocationMode = SaveLocationMode.ManagedInbox;

    [ObservableProperty]
    private AudioExportFormat selectedExportFormat = AudioExportFormat.M4b;

    [ObservableProperty]
    private string customSaveDirectory = string.Empty;

    [ObservableProperty]
    private string kokoroVoice = AppSettings.DefaultKokoroVoice;

    [ObservableProperty]
    private double kokoroSpeed = 1.0;

    [ObservableProperty]
    private string geminiModel = AppSettings.DefaultGeminiModel;

    [ObservableProperty]
    private string geminiVoice = AppSettings.DefaultGeminiVoice;

    [ObservableProperty]
    private string statusMessage = "Ready";

    [ObservableProperty]
    private string progressTitle = string.Empty;

    [ObservableProperty]
    private string progressDetail = string.Empty;

    [ObservableProperty]
    private double generationProgress;

    [ObservableProperty]
    private bool isGenerating;

    [ObservableProperty]
    private string lastSavedPath = string.Empty;

    [ObservableProperty]
    private string lastBackendLabel = string.Empty;

    [ObservableProperty]
    private string lastDeviceLabel = string.Empty;

    [ObservableProperty]
    private ImportedChapterItemViewModel? selectedChapter;

    [ObservableProperty]
    private string selectedChapterText = string.Empty;

    [ObservableProperty]
    private string generationTelemetry = "No active conversion yet.";

    [ObservableProperty]
    private bool isProgressIndeterminate;

    public bool IsBookMode => ImportedChapters.Count > 0;

    public Visibility ArticleWorkspaceVisibility => IsBookMode ? Visibility.Collapsed : Visibility.Visible;

    public Visibility BookWorkspaceVisibility => IsBookMode ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ProgressVisibility => IsGenerating || GenerationProgress > 0 ? Visibility.Visible : Visibility.Collapsed;

    public Visibility GenerateFullVisibility => IsBookMode ? Visibility.Visible : Visibility.Collapsed;

    public Visibility CustomFolderVisibility => SelectedSaveLocationMode == SaveLocationMode.CustomFolder ? Visibility.Visible : Visibility.Collapsed;

    public string HeaderSubtitle => IsBookMode
        ? "Imported EPUB workspace with chapter editing and full-book export."
        : "Paste article text or import an EPUB, then generate audio locally or with Gemini.";

    public string ImportedBookSummary => importedBook is null
        ? "No EPUB loaded."
        : $"{ImportedChapters.Count} chapters, {ImportedChapters.Count(static chapter => chapter.IsIncluded)} included, {ImportedChapters.Sum(static chapter => chapter.WordCount):N0} words";

    public string SelectedChapterHeading => SelectedChapter is null
        ? "Select a chapter"
        : $"Chapter {SelectedChapter.ImportOrder}: {SelectedChapter.Title}";

    public string SelectedChapterDetail => SelectedChapter is null
        ? "Pick a chapter from the organizer to review and edit its text."
        : $"{SelectedChapter.WordCount:N0} words{(SelectedChapter.HasEdits ? " | edited" : string.Empty)}";

    public string SaveLocationPreview => SelectedSaveLocationMode == SaveLocationMode.ManagedInbox
        ? $"{AppSettings.DefaultManagedInboxPath}\\<title-timestamp>\\<title-timestamp>.{SelectedExportFormat.FileExtension()}"
        : $"{(string.IsNullOrWhiteSpace(CustomSaveDirectory) ? "<choose-folder>" : CustomSaveDirectory)}\\<title-timestamp>\\<title-timestamp>.{SelectedExportFormat.FileExtension()}";

    public bool CanGenerateCurrent =>
        !IsGenerating &&
        !string.IsNullOrWhiteSpace(ArticleTitle) &&
        (!IsBookMode
            ? !string.IsNullOrWhiteSpace(ArticleBody)
            : SelectedChapter is not null && !string.IsNullOrWhiteSpace(SelectedChapter.WorkingText)) &&
        IsSaveLocationConfigured;

    public bool CanGenerateFullBook =>
        !IsGenerating &&
        IsBookMode &&
        ImportedChapters.Any(static chapter => chapter.IsIncluded && !string.IsNullOrWhiteSpace(chapter.WorkingText)) &&
        IsSaveLocationConfigured;

    public bool CanRevealLastFile => File.Exists(LastSavedPath);

    public bool CanClearBook => IsBookMode && !IsGenerating;

    public async Task InitializeAsync()
    {
        suppressPersistence = true;
        try
        {
            var settings = await settingsStore.LoadAsync();
            ArticleTitle = settings.DraftTitle;
            ArticleBody = settings.DraftBody;
            SelectedProviderMode = settings.ProviderMode;
            SelectedAccelerationMode = settings.AccelerationMode;
            SelectedSaveLocationMode = settings.SaveLocationMode;
            SelectedExportFormat = settings.ExportFormat;
            CustomSaveDirectory = settings.CustomSaveDirectory;
            KokoroVoice = settings.KokoroVoice;
            KokoroSpeed = settings.KokoroSpeed;
            GeminiModel = settings.GeminiModel;
            GeminiVoice = settings.GeminiVoice;
            lastKnownGoodBackend = settings.LastKnownGoodBackend;
            LastSavedPath = settings.LastSavedPath;
            LastBackendLabel = settings.LastBackendLabel;
            LastDeviceLabel = settings.LastDeviceLabel;
            geminiApiKey = await secretStore.ReadAsync("gemini_api_key") ?? string.Empty;
            StatusMessage = "Ready";
        }
        finally
        {
            suppressPersistence = false;
            RaiseComputedPropertyChanges();
        }
    }

    public string GetGeminiApiKey() => geminiApiKey;

    public async Task SetGeminiApiKeyAsync(string value)
    {
        geminiApiKey = value ?? string.Empty;
        await secretStore.SaveAsync("gemini_api_key", geminiApiKey);
    }

    public async Task ImportEpubAsync(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
        {
            return;
        }

        StatusMessage = $"Importing {Path.GetFileName(filePath)}...";
        var book = await Task.Run(() => epubImportService.Import(filePath));

        importedBook = book;
        foreach (var chapter in ImportedChapters)
        {
            chapter.PropertyChanged -= OnChapterChanged;
        }

        ImportedChapters.Clear();
        foreach (var chapter in book.Chapters)
        {
            var item = new ImportedChapterItemViewModel(
                chapter.Id,
                chapter.ImportOrder,
                chapter.Title,
                chapter.OriginalText,
                chapter.WorkingText,
                chapter.SourcePath,
                chapter.IsIncluded);
            item.PropertyChanged += OnChapterChanged;
            ImportedChapters.Add(item);
        }

        ArticleTitle = book.Title;
        SelectedChapter = ImportedChapters.FirstOrDefault();
        StatusMessage = $"Imported {book.Title} with {book.Chapters.Count} chapters.";
        RaiseComputedPropertyChanges();
    }

    public void ClearImportedBook()
    {
        importedBook = null;
        foreach (var chapter in ImportedChapters)
        {
            chapter.PropertyChanged -= OnChapterChanged;
        }

        ImportedChapters.Clear();
        SelectedChapter = null;
        SelectedChapterText = string.Empty;
        StatusMessage = "Cleared the imported book workspace.";
        RaiseComputedPropertyChanges();
    }

    public void ChooseCustomDirectory(string folderPath)
    {
        if (!string.IsNullOrWhiteSpace(folderPath))
        {
            CustomSaveDirectory = folderPath;
            StatusMessage = $"Saving custom exports into {folderPath}.";
        }
    }

    public async Task GenerateCurrentAsync()
    {
        if (!CanGenerateCurrent)
        {
            StatusMessage = "Enter a title, add text, and choose a save location before generating audio.";
            return;
        }

        IsGenerating = true;
        var text = IsBookMode ? SelectedChapter!.WorkingText : ArticleBody;
        var exportTitle = IsBookMode ? $"{ArticleTitle} chapter {SelectedChapter!.ImportOrder} {SelectedChapter.Title}" : ArticleTitle;
        var itemName = SlugHelper.MakeItemName(exportTitle);
        BeginGenerationTelemetry(
            payloadInfo: BuildCurrentPayloadInfo(text),
            exportTitle,
            itemName);
        SetProgressState("Preparing", "Setting up the Windows runtime", 0.05);
        RaiseComputedPropertyChanges();

        try
        {
            SetProgressState("Generating audio", "Running Kokoro or Gemini", 0.18, isIndeterminate: true);
            RecordGenerationEvent("Synthesis started.");
            var generated = await SynthesizeAsync(text);

            SetProgressState("Saving file", "Exporting the final audio", 0.82);
            RecordGenerationEvent($"Synthesis completed with {generated.BackendLabel} on {generated.DeviceLabel}.");
            var savedPath = await storageCoordinator.SaveAsync(
                new SaveAudioRequest(generated.WavData, itemName, SelectedExportFormat, exportTitle, importedBook?.Author),
                itemName,
                BuildSettingsSnapshot());

            LastSavedPath = savedPath;
            StatusMessage = $"Saved {Path.GetFileName(savedPath)}";
            SetProgressState("Completed", savedPath, 1.0);
            RecordGenerationEvent($"Saved {Path.GetFileName(savedPath)}.");
            await PersistSettingsAsync();
        }
        catch (Exception exception)
        {
            ApplyGenerationFailure(exception, "audio");
        }
        finally
        {
            StopGenerationTelemetry();
            IsGenerating = false;
            RaiseComputedPropertyChanges();
        }
    }

    public async Task GenerateFullBookAsync()
    {
        if (!CanGenerateFullBook || importedBook is null)
        {
            StatusMessage = "Import an EPUB and include at least one chapter before generating a full audiobook.";
            return;
        }

        var included = ImportedChapters.Where(static chapter => chapter.IsIncluded && !string.IsNullOrWhiteSpace(chapter.WorkingText)).ToArray();
        if (included.Length == 0)
        {
            StatusMessage = "No included chapters have text to synthesize.";
            return;
        }

        IsGenerating = true;
        var totalWords = included.Sum(static chapter => chapter.WordCount);
        var totalCharacters = included.Sum(static chapter => chapter.WorkingText.Length);
        var itemName = SlugHelper.MakeItemName(ArticleTitle);
        BeginGenerationTelemetry(
            payloadInfo: $"Audiobook export: {included.Length} chapter(s) | {totalWords:N0} words | {totalCharacters:N0} chars",
            ArticleTitle,
            itemName);
        SetProgressState("Generating audiobook", $"Preparing {included.Length} chapter(s)", 0.02);
        RaiseComputedPropertyChanges();

        try
        {
            var chapterSegments = new List<ChapterWavSegment>(included.Length);
            for (var index = 0; index < included.Length; index++)
            {
                var chapter = included[index];
                SetProgressState(
                    "Generating audiobook",
                    $"Generating chapter {index + 1} of {included.Length}: {chapter.Title}",
                    0.05 + (0.65 * (index / (double)included.Length)),
                    isIndeterminate: false);
                RecordGenerationEvent($"Started chapter {index + 1}/{included.Length}: {chapter.Title}");

                var generated = await SynthesizeAsync(chapter.WorkingText);
                chapterSegments.Add(new ChapterWavSegment(chapter.Title, generated.WavData));
                RecordGenerationEvent($"Finished chapter {index + 1}/{included.Length} with {generated.BackendLabel}.");
            }

            SetProgressState("Stitching chapters", "Combining chapter WAV files", 0.78);
            RecordGenerationEvent("Combining chapter WAV files.");
            var stitched = wavStitcher.Stitch(chapterSegments);

            SetProgressState("Saving audiobook", "Exporting audiobook package", 0.9);
            RecordGenerationEvent($"Prepared stitched WAV with {stitched.ChapterMarkers.Count} chapter marker(s).");
            var savedPath = await storageCoordinator.SaveAsync(
                new SaveAudioRequest(
                    stitched.WavData,
                    itemName,
                    SelectedExportFormat,
                    ArticleTitle,
                    importedBook.Author,
                    stitched.ChapterMarkers,
                    importedBook.CoverImageData),
                itemName,
                BuildSettingsSnapshot());

            LastSavedPath = savedPath;
            StatusMessage = $"Saved audiobook {Path.GetFileName(savedPath)}";
            SetProgressState("Completed", savedPath, 1.0);
            RecordGenerationEvent($"Saved audiobook {Path.GetFileName(savedPath)}.");
            await PersistSettingsAsync();
        }
        catch (Exception exception)
        {
            ApplyGenerationFailure(exception, "the audiobook");
        }
        finally
        {
            StopGenerationTelemetry();
            IsGenerating = false;
            RaiseComputedPropertyChanges();
        }
    }

    public void RevealLastFile()
    {
        if (!CanRevealLastFile)
        {
            return;
        }

        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = $"/select,\"{LastSavedPath}\"",
            UseShellExecute = true
        });
    }

    public void RevertSelectedChapterText()
    {
        if (SelectedChapter is null)
        {
            return;
        }

        SelectedChapter.WorkingText = SelectedChapter.OriginalText;
        SelectedChapterText = SelectedChapter.OriginalText;
    }

    partial void OnArticleTitleChanged(string value) => PersistAndRefresh();
    partial void OnArticleBodyChanged(string value) => PersistAndRefresh();
    partial void OnSelectedProviderModeChanged(ProviderMode value) => PersistAndRefresh();
    partial void OnSelectedAccelerationModeChanged(AccelerationMode value) => PersistAndRefresh();
    partial void OnSelectedSaveLocationModeChanged(SaveLocationMode value) => PersistAndRefresh();
    partial void OnSelectedExportFormatChanged(AudioExportFormat value) => PersistAndRefresh();
    partial void OnCustomSaveDirectoryChanged(string value) => PersistAndRefresh();
    partial void OnKokoroVoiceChanged(string value) => PersistAndRefresh();
    partial void OnKokoroSpeedChanged(double value) => PersistAndRefresh();
    partial void OnGeminiModelChanged(string value) => PersistAndRefresh();
    partial void OnGeminiVoiceChanged(string value) => PersistAndRefresh();
    partial void OnLastSavedPathChanged(string value) => PersistAndRefresh();
    partial void OnLastBackendLabelChanged(string value) => PersistAndRefresh();
    partial void OnLastDeviceLabelChanged(string value) => PersistAndRefresh();

    partial void OnSelectedChapterChanged(ImportedChapterItemViewModel? value)
    {
        SelectedChapterText = value?.WorkingText ?? string.Empty;
        OnPropertyChanged(nameof(SelectedChapterHeading));
        OnPropertyChanged(nameof(SelectedChapterDetail));
        OnPropertyChanged(nameof(CanGenerateCurrent));
    }

    partial void OnSelectedChapterTextChanged(string value)
    {
        if (SelectedChapter is not null && !string.Equals(SelectedChapter.WorkingText, value, StringComparison.Ordinal))
        {
            SelectedChapter.WorkingText = value;
            OnPropertyChanged(nameof(SelectedChapterDetail));
            RaiseComputedPropertyChanges();
        }
    }

    private void OnChapterChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (SelectedChapter is not null &&
            sender == SelectedChapter &&
            e.PropertyName == nameof(ImportedChapterItemViewModel.WorkingText))
        {
            if (!string.Equals(SelectedChapterText, SelectedChapter.WorkingText, StringComparison.Ordinal))
            {
                SelectedChapterText = SelectedChapter.WorkingText;
            }
        }

        RaiseComputedPropertyChanges();
    }

    private async Task<(byte[] WavData, string BackendLabel, string DeviceLabel)> SynthesizeAsync(string text)
    {
        switch (SelectedProviderMode)
        {
        case ProviderMode.GeminiOnly:
            return await SynthesizeWithGeminiAsync(text);
        case ProviderMode.Automatic:
            try
            {
                return await SynthesizeWithKokoroAsync(text);
            }
            catch (Exception) when (!string.IsNullOrWhiteSpace(geminiApiKey))
            {
                StatusMessage = "Local generation failed. Falling back to Gemini...";
                return await SynthesizeWithGeminiAsync(text);
            }
        default:
            return await SynthesizeWithKokoroAsync(text);
        }
    }

    private async Task<(byte[] WavData, string BackendLabel, string DeviceLabel)> SynthesizeWithKokoroAsync(string text)
    {
        var settings = await settingsStore.LoadAsync();
        var progress = new Progress<KokoroRuntimeUpdate>(OnKokoroRuntimeUpdate);
        var result = await kokoroSynthesizer.SynthesizeAsync(
            new SynthesisRequest(text, KokoroVoice, KokoroSpeed, SelectedAccelerationMode, lastKnownGoodBackend ?? settings.LastKnownGoodBackend),
            progress);
        lastKnownGoodBackend = result.Backend;
        settings.LastKnownGoodBackend = result.Backend;
        await settingsStore.SaveAsync(settings);
        LastBackendLabel = result.BackendLabel;
        LastDeviceLabel = result.DeviceLabel;
        return (result.AudioData, result.BackendLabel, result.DeviceLabel);
    }

    private async Task<(byte[] WavData, string BackendLabel, string DeviceLabel)> SynthesizeWithGeminiAsync(string text)
    {
        generationBackendPlanInfo = "Backend plan: Gemini cloud synthesis";
        generationRuntimeInfo = $"Runtime: Gemini model {GeminiModel}";
        generationWorkerInfo = "Worker: Gemini cloud request";
        RecordGenerationEvent($"Sending request to Gemini model {GeminiModel}.");
        var result = await geminiTtsClient.SynthesizeAsync(text, geminiApiKey, GeminiModel, GeminiVoice);
        var wavData = WavEncoder.WrapIfNeeded(result.AudioData, result.MimeType);
        LastBackendLabel = "Gemini";
        LastDeviceLabel = "Cloud";
        RecordGenerationEvent("Gemini audio returned.");
        return (wavData, "Gemini", "Cloud");
    }

    private void ApplyGenerationFailure(Exception exception, string outputLabel)
    {
        SetProgressState("Generation failed", BuildFailureDetail(exception), 0);
        StatusMessage = BuildFailureStatusMessage(exception, outputLabel);
        RecordGenerationEvent($"Generation failed: {ExtractReadableError(exception)}");
    }

    private string BuildFailureStatusMessage(Exception exception, string outputLabel)
    {
        if (IsDirectMlUnsupported(exception))
        {
            return "DirectML is not supported for Kokoro on this GPU yet. Switch Acceleration to Auto or CPU and try again.";
        }

        if (IsMissingKokoroRuntime(exception))
        {
            return "Kokoro runtime is missing. Install the Windows runtime and try again.";
        }

        return $"Could not generate {outputLabel}: {ExtractReadableError(exception)}";
    }

    private string BuildFailureDetail(Exception exception)
    {
        if (IsDirectMlUnsupported(exception))
        {
            return "This Windows GPU/runtime combination hit an unsupported torch-directml LSTM path.";
        }

        if (IsMissingKokoroRuntime(exception))
        {
            return "No local Kokoro runtime was found for the selected backend.";
        }

        return ExtractReadableError(exception);
    }

    private static bool IsDirectMlUnsupported(Exception exception)
    {
        var details = exception.ToString();
        return details.Contains("DirectML", StringComparison.OrdinalIgnoreCase) &&
            (details.Contains("torch-directml", StringComparison.OrdinalIgnoreCase) ||
             details.Contains("_thnn_fused_lstm_cell", StringComparison.OrdinalIgnoreCase) ||
             details.Contains("DML backend", StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsMissingKokoroRuntime(Exception exception)
    {
        return exception.ToString().Contains("runtime not found", StringComparison.OrdinalIgnoreCase);
    }

    private static string ExtractReadableError(Exception exception)
    {
        var message = exception.GetBaseException().Message;
        if (string.IsNullOrWhiteSpace(message))
        {
            return "Unknown Windows runtime error.";
        }

        var firstLine = message
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault();

        if (string.IsNullOrWhiteSpace(firstLine))
        {
            return "Unknown Windows runtime error.";
        }

        const int maxLength = 140;
        return firstLine.Length <= maxLength ? firstLine : $"{firstLine[..(maxLength - 3)]}...";
    }

    private void BeginGenerationTelemetry(string payloadInfo, string exportTitle, string itemName)
    {
        generationTelemetryCts?.Cancel();
        generationTelemetryCts = new CancellationTokenSource();
        generationStartedAt = DateTimeOffset.Now;
        generationElapsedText = "Elapsed: 00:00";
        progressDetailBase = string.Empty;
        generationEvents.Clear();
        generationSourceInfo = payloadInfo;
        generationRequestInfo = $"Request: {LookupProviderLabel(SelectedProviderMode)} | {LookupAccelerationLabel(SelectedAccelerationMode)} | {KokoroVoice} at {KokoroSpeed:0.00}x";
        generationOutputInfo = $"Output: {SelectedExportFormat.Title()} | {LookupSaveLocationLabel(SelectedSaveLocationMode)} | {BuildSaveTargetPreview(exportTitle, itemName)}";
        generationBackendPlanInfo = "Backend plan: resolving Windows runtime order...";
        generationRuntimeInfo = "Runtime: waiting for synthesis provider";
        generationWorkerInfo = "Worker: waiting to start";
        generationScratchInfo = string.Empty;
        RecordGenerationEvent("Generation requested.");
        _ = RunGenerationTelemetryTickerAsync(generationTelemetryCts.Token);
    }

    private async Task RunGenerationTelemetryTickerAsync(CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                if (generationStartedAt is not null)
                {
                    var elapsed = DateTimeOffset.Now - generationStartedAt.Value;
                    generationElapsedText = $"Elapsed: {elapsed:mm\\:ss}";
                    RefreshProgressDetail();
                    RefreshGenerationTelemetry();
                }

                await Task.Delay(1000, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
            // Expected when generation completes or a new generation starts.
        }
    }

    private void SetProgressState(string title, string detail, double progress, bool isIndeterminate = false)
    {
        ProgressTitle = title;
        progressDetailBase = detail;
        GenerationProgress = progress;
        IsProgressIndeterminate = isIndeterminate;
        RefreshProgressDetail();
        RefreshGenerationTelemetry();
    }

    private void RefreshProgressDetail()
    {
        ProgressDetail = (string.IsNullOrWhiteSpace(progressDetailBase), string.IsNullOrWhiteSpace(generationElapsedText)) switch
        {
            (true, true) => string.Empty,
            (false, true) => progressDetailBase,
            (true, false) => generationElapsedText,
            _ => $"{progressDetailBase} | {generationElapsedText}"
        };
    }

    private void OnKokoroRuntimeUpdate(KokoroRuntimeUpdate update)
    {
        if (update.CandidateOrder is { Count: > 0 })
        {
            generationBackendPlanInfo = $"Backend plan: {string.Join(" -> ", update.CandidateOrder.Select(static backend => FormatBackend(backend)))}";
        }

        if (!string.IsNullOrWhiteSpace(update.RuntimePythonPath))
        {
            generationRuntimeInfo = $"Runtime: {update.RuntimePythonPath}";
        }

        if (!string.IsNullOrWhiteSpace(update.WorkingDirectory))
        {
            generationScratchInfo = $"Scratch: {update.WorkingDirectory}";
        }

        if (update.WorkerProcessId is int pid)
        {
            generationWorkerInfo = $"Worker: pid {pid} | backend {FormatBackend(update.Backend)}";
        }
        else if (update.Backend is not null)
        {
            generationWorkerInfo = $"Worker: backend {FormatBackend(update.Backend)}";
        }

        RecordGenerationEvent(update.Message);
    }

    private void RecordGenerationEvent(string message)
    {
        generationEvents.Add($"{DateTimeOffset.Now:HH:mm:ss} {message}");
        while (generationEvents.Count > 8)
        {
            generationEvents.RemoveAt(0);
        }

        RefreshGenerationTelemetry();
    }

    private void RefreshGenerationTelemetry()
    {
        var lines = new List<string>();
        if (!string.IsNullOrWhiteSpace(ProgressTitle))
        {
            lines.Add($"Phase: {ProgressTitle}");
        }

        if (!string.IsNullOrWhiteSpace(generationElapsedText))
        {
            lines.Add(generationElapsedText);
        }

        if (!string.IsNullOrWhiteSpace(generationSourceInfo))
        {
            lines.Add(generationSourceInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationRequestInfo))
        {
            lines.Add(generationRequestInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationOutputInfo))
        {
            lines.Add(generationOutputInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationBackendPlanInfo))
        {
            lines.Add(generationBackendPlanInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationRuntimeInfo))
        {
            lines.Add(generationRuntimeInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationWorkerInfo))
        {
            lines.Add(generationWorkerInfo);
        }

        if (!string.IsNullOrWhiteSpace(generationScratchInfo))
        {
            lines.Add(generationScratchInfo);
        }

        if (generationEvents.Count > 0)
        {
            lines.Add("Recent events:");
            lines.AddRange(generationEvents.Select(static entry => $"  {entry}"));
        }

        GenerationTelemetry = lines.Count == 0
            ? "No active conversion yet."
            : string.Join(Environment.NewLine, lines);
    }

    private void StopGenerationTelemetry()
    {
        if (generationStartedAt is not null)
        {
            var elapsed = DateTimeOffset.Now - generationStartedAt.Value;
            generationElapsedText = $"Elapsed: {elapsed:mm\\:ss}";
        }

        generationStartedAt = null;
        generationTelemetryCts?.Cancel();
        generationTelemetryCts = null;
        IsProgressIndeterminate = false;
        RefreshProgressDetail();
        RefreshGenerationTelemetry();
    }

    private string BuildCurrentPayloadInfo(string text) =>
        $"Payload: {(IsBookMode ? $"Chapter {SelectedChapter?.ImportOrder}: {SelectedChapter?.Title}" : "Article")} | {CountWords(text):N0} words | {text.Length:N0} chars";

    private static int CountWords(string text) =>
        string.IsNullOrWhiteSpace(text)
            ? 0
            : text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    private string BuildSaveTargetPreview(string exportTitle, string itemName)
    {
        var targetRoot = SelectedSaveLocationMode == SaveLocationMode.ManagedInbox
            ? AppSettings.DefaultManagedInboxPath
            : (string.IsNullOrWhiteSpace(CustomSaveDirectory) ? "<choose-folder>" : CustomSaveDirectory);
        var fileName = $"{itemName}.{SelectedExportFormat.FileExtension()}";
        return $"{targetRoot}\\{itemName}\\{fileName}";
    }

    private string LookupProviderLabel(ProviderMode mode) =>
        ProviderOptions.First(option => option.Value.Equals(mode)).Label;

    private string LookupAccelerationLabel(AccelerationMode mode) =>
        AccelerationOptions.First(option => option.Value.Equals(mode)).Label;

    private string LookupSaveLocationLabel(SaveLocationMode mode) =>
        SaveLocationOptions.First(option => option.Value.Equals(mode)).Label;

    private static string FormatBackend(ResolvedLocalBackend backend) => FormatBackend((ResolvedLocalBackend?)backend);

    private static string FormatBackend(ResolvedLocalBackend? backend) => backend switch
    {
        ResolvedLocalBackend.Cuda => "CUDA",
        ResolvedLocalBackend.DirectML => "DirectML",
        ResolvedLocalBackend.Cpu => "CPU",
        _ => "unknown"
    };

    private void PersistAndRefresh()
    {
        RaiseComputedPropertyChanges();
        if (!suppressPersistence)
        {
            _ = PersistSettingsAsync();
        }
    }

    private async Task PersistSettingsAsync()
    {
        if (!suppressPersistence)
        {
            await settingsStore.SaveAsync(BuildSettingsSnapshot());
        }
    }

    private AppSettings BuildSettingsSnapshot() => new()
    {
        DraftTitle = ArticleTitle,
        DraftBody = ArticleBody,
        ProviderMode = SelectedProviderMode,
        AccelerationMode = SelectedAccelerationMode,
        SaveLocationMode = SelectedSaveLocationMode,
        ExportFormat = SelectedExportFormat,
        CustomSaveDirectory = CustomSaveDirectory,
        KokoroVoice = KokoroVoice,
        KokoroSpeed = KokoroSpeed,
        GeminiModel = GeminiModel,
        GeminiVoice = GeminiVoice,
        LastSavedPath = LastSavedPath,
        LastBackendLabel = LastBackendLabel,
        LastDeviceLabel = LastDeviceLabel,
        LastKnownGoodBackend = lastKnownGoodBackend
    };

    private bool IsSaveLocationConfigured =>
        SelectedSaveLocationMode == SaveLocationMode.ManagedInbox || !string.IsNullOrWhiteSpace(CustomSaveDirectory);

    private void RaiseComputedPropertyChanges()
    {
        OnPropertyChanged(nameof(IsBookMode));
        OnPropertyChanged(nameof(ArticleWorkspaceVisibility));
        OnPropertyChanged(nameof(BookWorkspaceVisibility));
        OnPropertyChanged(nameof(ProgressVisibility));
        OnPropertyChanged(nameof(GenerateFullVisibility));
        OnPropertyChanged(nameof(CustomFolderVisibility));
        OnPropertyChanged(nameof(HeaderSubtitle));
        OnPropertyChanged(nameof(ImportedBookSummary));
        OnPropertyChanged(nameof(SelectedChapterHeading));
        OnPropertyChanged(nameof(SelectedChapterDetail));
        OnPropertyChanged(nameof(SaveLocationPreview));
        OnPropertyChanged(nameof(CanGenerateCurrent));
        OnPropertyChanged(nameof(CanGenerateFullBook));
        OnPropertyChanged(nameof(CanRevealLastFile));
        OnPropertyChanged(nameof(CanClearBook));
    }
}
