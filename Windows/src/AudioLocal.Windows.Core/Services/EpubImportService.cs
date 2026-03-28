using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using AudioLocal.Windows.Core.Models;
using HtmlAgilityPack;

namespace AudioLocal.Windows.Core.Services;

public sealed class EpubImportService
{
    private static readonly Regex ChapterPattern = new(
        "(chapter|part|split|ch[_-]?\\d{1,3}|chap[_-]?\\d{1,3})",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public ImportedBook Import(string filePath)
    {
        if (!File.Exists(filePath) || !filePath.EndsWith(".epub", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Only EPUB imports are supported right now.");
        }

        using var archive = ZipFile.OpenRead(filePath);
        var containerEntry = archive.GetEntry("META-INF/container.xml")
            ?? throw new InvalidOperationException("The EPUB is missing META-INF/container.xml.");
        var packagePath = ReadPackagePath(containerEntry)
            ?? throw new InvalidOperationException("The EPUB container does not describe a root package.");
        var packageEntry = archive.GetEntry(NormalizeZipPath(packagePath))
            ?? throw new InvalidOperationException("The EPUB package file is missing.");

        var packageDocument = XDocument.Load(packageEntry.Open());
        XNamespace opfNamespace = packageDocument.Root?.Name.Namespace ?? XNamespace.None;
        var metadata = packageDocument.Root?.Element(opfNamespace + "metadata");
        var manifest = packageDocument.Root?.Element(opfNamespace + "manifest");
        var spine = packageDocument.Root?.Element(opfNamespace + "spine");
        if (manifest is null || spine is null)
        {
            throw new InvalidOperationException("The EPUB package file is invalid.");
        }

        var manifestItems = manifest.Elements(opfNamespace + "item")
            .Select(static element => new ManifestItem(
                element.Attribute("id")?.Value ?? string.Empty,
                element.Attribute("href")?.Value ?? string.Empty,
                element.Attribute("media-type")?.Value ?? string.Empty,
                element.Attribute("properties")?.Value ?? string.Empty))
            .Where(static item => !string.IsNullOrWhiteSpace(item.Id) && !string.IsNullOrWhiteSpace(item.Href))
            .ToDictionary(static item => item.Id, StringComparer.Ordinal);

        var packageDirectory = GetDirectoryName(packagePath);
        var rawChapters = new List<ImportedChapter>();

        foreach (var itemRef in spine.Elements(opfNamespace + "itemref"))
        {
            var idRef = itemRef.Attribute("idref")?.Value;
            if (string.IsNullOrWhiteSpace(idRef) || !manifestItems.TryGetValue(idRef, out var item) || !item.IsReadableChapter)
            {
                continue;
            }

            var chapterPath = CombineZipPath(packageDirectory, item.Href.Split('#')[0]);
            var chapterEntry = archive.GetEntry(chapterPath);
            if (chapterEntry is null)
            {
                continue;
            }

            using var stream = chapterEntry.Open();
            using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            var html = reader.ReadToEnd();
            var extracted = ExtractChapterText(html);
            if (string.IsNullOrWhiteSpace(extracted.Text))
            {
                continue;
            }

            rawChapters.Add(new ImportedChapter
            {
                Id = Guid.NewGuid(),
                ImportOrder = rawChapters.Count + 1,
                Title = extracted.Title ?? PrettyStem(item.Href, rawChapters.Count + 1),
                OriginalText = extracted.Text,
                WorkingText = extracted.Text,
                SourcePath = item.Href,
                IsIncluded = false
            });
        }

        if (rawChapters.Count == 0)
        {
            throw new InvalidOperationException("This EPUB did not contain any readable XHTML chapters.");
        }

        ApplyAudiblezChapterHeuristics(rawChapters);
        var (coverData, coverMimeType) = TryReadCover(archive, metadata, manifestItems, packageDirectory);

        return new ImportedBook
        {
            Title = metadata?.Elements().FirstOrDefault(static element => element.Name.LocalName.Equals("title", StringComparison.OrdinalIgnoreCase))?.Value
                ?.Trim() ?? Path.GetFileNameWithoutExtension(filePath),
            Author = metadata?.Elements().FirstOrDefault(static element => element.Name.LocalName.Equals("creator", StringComparison.OrdinalIgnoreCase))?.Value?.Trim(),
            SourcePath = filePath,
            Chapters = rawChapters,
            CoverImageData = coverData,
            CoverMimeType = coverMimeType
        };
    }

    private static string? ReadPackagePath(ZipArchiveEntry containerEntry)
    {
        var document = XDocument.Load(containerEntry.Open());
        return document.Descendants()
            .FirstOrDefault(static element => element.Name.LocalName.Equals("rootfile", StringComparison.OrdinalIgnoreCase))
            ?.Attribute("full-path")?.Value;
    }

    private static void ApplyAudiblezChapterHeuristics(List<ImportedChapter> chapters)
    {
        var goodChapters = chapters.Where(static chapter =>
            chapter.OriginalText.Length > 100 &&
            ChapterPattern.IsMatch(chapter.SourcePath)).ToArray();

        if (goodChapters.Length == 0)
        {
            foreach (var chapter in chapters.Where(static chapter => chapter.OriginalText.Length > 10))
            {
                chapter.IsIncluded = true;
            }

            return;
        }

        foreach (var chapter in goodChapters)
        {
            chapter.IsIncluded = true;
        }
    }

    private static (string? Title, string Text) ExtractChapterText(string html)
    {
        var document = new HtmlDocument();
        document.LoadHtml(html);

        var title = document.DocumentNode.SelectSingleNode("//title")?.InnerText?.Trim();
        title ??= document.DocumentNode.SelectSingleNode("//h1")?.InnerText?.Trim();
        title ??= document.DocumentNode.SelectSingleNode("//h2")?.InnerText?.Trim();

        var nodes = document.DocumentNode.SelectNodes("//title|//p|//h1|//h2|//h3|//h4|//li");
        var lines = new List<string>();
        if (nodes is not null)
        {
            foreach (var node in nodes)
            {
                var text = HtmlEntity.DeEntitize(node.InnerText ?? string.Empty).Trim();
                if (string.IsNullOrWhiteSpace(text))
                {
                    continue;
                }

                if (!EndsWithSentenceTerminal(text))
                {
                    text += ".";
                }

                lines.Add(text);
            }
        }

        var content = NormalizeText(string.Join(Environment.NewLine, lines));
        if (string.IsNullOrWhiteSpace(content))
        {
            var fallbackText = NormalizeText(HtmlEntity.DeEntitize(document.DocumentNode.InnerText ?? string.Empty));
            return (title, fallbackText);
        }

        return (NormalizeText(title ?? string.Empty), content);
    }

    private static (byte[]? Data, string? MimeType) TryReadCover(
        ZipArchive archive,
        XElement? metadata,
        IReadOnlyDictionary<string, ManifestItem> manifestItems,
        string packageDirectory)
    {
        var coverItem = manifestItems.Values.FirstOrDefault(static item =>
                item.Properties.Contains("cover-image", StringComparison.OrdinalIgnoreCase)) ??
            ResolveLegacyCover(metadata, manifestItems) ??
            manifestItems.Values.FirstOrDefault(static item =>
                item.MediaType.StartsWith("image/", StringComparison.OrdinalIgnoreCase) &&
                item.Href.Contains("cover", StringComparison.OrdinalIgnoreCase));

        if (coverItem is null)
        {
            return (null, null);
        }

        var entry = archive.GetEntry(CombineZipPath(packageDirectory, coverItem.Href));
        if (entry is null)
        {
            return (null, null);
        }

        using var stream = entry.Open();
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return (memory.ToArray(), coverItem.MediaType);
    }

    private static ManifestItem? ResolveLegacyCover(XElement? metadata, IReadOnlyDictionary<string, ManifestItem> manifestItems)
    {
        var coverId = metadata?
            .Elements()
            .FirstOrDefault(static element =>
                element.Name.LocalName.Equals("meta", StringComparison.OrdinalIgnoreCase) &&
                string.Equals(element.Attribute("name")?.Value, "cover", StringComparison.OrdinalIgnoreCase))
            ?.Attribute("content")?.Value;

        if (coverId is not null && manifestItems.TryGetValue(coverId, out var item))
        {
            return item;
        }

        return null;
    }

    private static bool EndsWithSentenceTerminal(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var last = value[^1];
        return last is '.' or '!' or '?' or ':' or ';';
    }

    private static string NormalizeText(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Replace('\u00A0', ' ');
        normalized = Regex.Replace(normalized, "[ \\t]+\\n", "\n");
        normalized = Regex.Replace(normalized, "\\n{3,}", "\n\n");
        normalized = Regex.Replace(normalized, "[ \\t]{2,}", " ");
        return normalized.Trim();
    }

    private static string PrettyStem(string href, int index)
    {
        var stem = Path.GetFileNameWithoutExtension(href.Replace('/', Path.DirectorySeparatorChar));
        stem = Regex.Replace(stem, "[_-]+", " ").Trim();
        return string.IsNullOrWhiteSpace(stem)
            ? $"Chapter {index}"
            : string.Join(' ', stem.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(static value => Capitalize(value)));
    }

    private static string Capitalize(string value) =>
        string.IsNullOrWhiteSpace(value) ? value : char.ToUpperInvariant(value[0]) + value[1..];

    private static string NormalizeZipPath(string path) => path.Replace('\\', '/');

    private static string CombineZipPath(string prefix, string relative) =>
        string.IsNullOrWhiteSpace(prefix)
            ? NormalizeZipPath(relative)
            : NormalizeZipPath($"{prefix.TrimEnd('/')}/{relative.TrimStart('/')}");

    private static string GetDirectoryName(string path)
    {
        var normalized = NormalizeZipPath(path);
        var lastSlash = normalized.LastIndexOf('/');
        return lastSlash <= 0 ? string.Empty : normalized[..lastSlash];
    }

    private sealed record ManifestItem(string Id, string Href, string MediaType, string Properties)
    {
        public bool IsReadableChapter =>
            !Properties.Contains("nav", StringComparison.OrdinalIgnoreCase) &&
            (MediaType.Contains("html", StringComparison.OrdinalIgnoreCase) ||
             MediaType.Contains("xhtml", StringComparison.OrdinalIgnoreCase) ||
             MediaType.Contains("xml", StringComparison.OrdinalIgnoreCase));
    }
}
