namespace AudioLocal.Windows.Core.Infrastructure;

public static class SlugHelper
{
    public static string MakeItemName(string rawTitle, DateTimeOffset? now = null)
    {
        var title = (rawTitle ?? string.Empty).Trim();
        var normalized = new string(title
            .ToLowerInvariant()
            .Select(static character => char.IsLetterOrDigit(character) ? character : '-')
            .ToArray());

        while (normalized.Contains("--", StringComparison.Ordinal))
        {
            normalized = normalized.Replace("--", "-", StringComparison.Ordinal);
        }

        normalized = normalized.Trim('-');
        var timestamp = (now ?? DateTimeOffset.Now).ToString("yyyyMMdd-HHmmss");
        return $"{(string.IsNullOrWhiteSpace(normalized) ? "article" : normalized)}-{timestamp}";
    }
}
