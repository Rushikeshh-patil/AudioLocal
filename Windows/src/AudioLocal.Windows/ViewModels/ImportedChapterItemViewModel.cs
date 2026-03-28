using CommunityToolkit.Mvvm.ComponentModel;

namespace AudioLocal.Windows.ViewModels;

public partial class ImportedChapterItemViewModel : ObservableObject
{
    public ImportedChapterItemViewModel(Guid id, int importOrder, string title, string originalText, string workingText, string sourcePath, bool isIncluded)
    {
        Id = id;
        ImportOrder = importOrder;
        this.title = title;
        OriginalText = originalText;
        this.workingText = workingText;
        SourcePath = sourcePath;
        this.isIncluded = isIncluded;
    }

    public Guid Id { get; }

    public int ImportOrder { get; }

    public string OriginalText { get; }

    public string SourcePath { get; }

    [ObservableProperty]
    private string title;

    [ObservableProperty]
    private string workingText;

    [ObservableProperty]
    private bool isIncluded;

    public int WordCount => string.IsNullOrWhiteSpace(WorkingText)
        ? 0
        : WorkingText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    public bool HasEdits => !string.Equals(WorkingText, OriginalText, StringComparison.Ordinal);

    partial void OnWorkingTextChanged(string value)
    {
        OnPropertyChanged(nameof(WordCount));
        OnPropertyChanged(nameof(HasEdits));
    }
}
