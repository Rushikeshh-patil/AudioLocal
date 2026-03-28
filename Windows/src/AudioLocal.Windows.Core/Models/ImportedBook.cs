namespace AudioLocal.Windows.Core.Models;

public sealed class ImportedBook
{
    public required string Title { get; init; }
    public string? Author { get; init; }
    public required string SourcePath { get; init; }
    public required IReadOnlyList<ImportedChapter> Chapters { get; init; }
    public byte[]? CoverImageData { get; init; }
    public string? CoverMimeType { get; init; }

    public int TotalWordCount => Chapters.Sum(static chapter => chapter.WordCount);

    public IReadOnlyList<ImportedChapter> IncludedChapters =>
        Chapters.Where(static chapter => chapter.IsIncluded).ToArray();
}

public sealed class ImportedChapter
{
    public required Guid Id { get; init; }
    public required int ImportOrder { get; init; }
    public required string Title { get; set; }
    public required string OriginalText { get; init; }
    public required string WorkingText { get; set; }
    public required string SourcePath { get; init; }
    public bool IsIncluded { get; set; } = true;

    public int WordCount => string.IsNullOrWhiteSpace(WorkingText)
        ? 0
        : WorkingText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;

    public bool HasEdits => !string.Equals(WorkingText, OriginalText, StringComparison.Ordinal);
}
