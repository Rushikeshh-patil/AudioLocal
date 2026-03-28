using System.IO.Compression;
using System.Text;
using AudioLocal.Windows.Core.Services;

namespace AudioLocal.Windows.Core.Tests;

public sealed class EpubImportServiceTests : IDisposable
{
    private readonly string tempRoot = Path.Combine(Path.GetTempPath(), "AudioLocal.Tests", Guid.NewGuid().ToString("N"));

    public EpubImportServiceTests()
    {
        Directory.CreateDirectory(tempRoot);
    }

    [Fact]
    public void ImportMarksOnlyChapterLikeFilesIncludedWhenHeuristicsMatch()
    {
        var epubPath = CreateEpub(
            "heuristic.epub",
            "Heuristic Book",
            "Test Author",
            [
                new EpubItem("chapter_001.xhtml", HtmlDocument("Chapter 1", LongParagraph("First chapter"))),
                new EpubItem("chapter_002.xhtml", HtmlDocument("Chapter 2", LongParagraph("Second chapter"))),
                new EpubItem("preface.xhtml", HtmlDocument("Preface", LongParagraph("Preface section")))
            ]);

        var service = new EpubImportService();
        var result = service.Import(epubPath);

        Assert.Equal("Heuristic Book", result.Title);
        Assert.Equal("Test Author", result.Author);
        Assert.Collection(
            result.Chapters,
            chapter =>
            {
                Assert.Equal("Chapter 1", chapter.Title);
                Assert.True(chapter.IsIncluded);
            },
            chapter =>
            {
                Assert.Equal("Chapter 2", chapter.Title);
                Assert.True(chapter.IsIncluded);
            },
            chapter =>
            {
                Assert.Equal("Preface", chapter.Title);
                Assert.False(chapter.IsIncluded);
            });
    }

    [Fact]
    public void ImportFallsBackToIncludingAllReadableFilesWhenNoChapterPatternMatches()
    {
        var epubPath = CreateEpub(
            "fallback.epub",
            "Fallback Book",
            "Test Author",
            [
                new EpubItem("intro.xhtml", HtmlDocument("Intro", LongParagraph("Introduction"))),
                new EpubItem("body.xhtml", HtmlDocument("Body", LongParagraph("Body text")))
            ]);

        var service = new EpubImportService();
        var result = service.Import(epubPath);

        Assert.All(result.Chapters, chapter => Assert.True(chapter.IsIncluded));
    }

    [Fact]
    public void ImportReadsCoverImageFromManifestCoverProperty()
    {
        var epubPath = CreateEpub(
            "cover.epub",
            "Cover Book",
            "Test Author",
            [new EpubItem("chapter_001.xhtml", HtmlDocument("Chapter 1", LongParagraph("Covered chapter")))],
            new EpubCover("images/cover.jpg", "image/jpeg", [0x01, 0x02, 0x03, 0x04]));

        var service = new EpubImportService();
        var result = service.Import(epubPath);

        Assert.Equal("image/jpeg", result.CoverMimeType);
        Assert.Equal(new byte[] { 0x01, 0x02, 0x03, 0x04 }, result.CoverImageData);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(tempRoot, recursive: true);
        }
        catch
        {
            // Best-effort cleanup for temp files.
        }
    }

    private string CreateEpub(
        string fileName,
        string title,
        string author,
        IReadOnlyList<EpubItem> chapterItems,
        EpubCover? cover = null)
    {
        var filePath = Path.Combine(tempRoot, fileName);
        using var archive = ZipFile.Open(filePath, ZipArchiveMode.Create);

        var mimeTypeEntry = archive.CreateEntry("mimetype", CompressionLevel.NoCompression);
        using (var writer = new StreamWriter(mimeTypeEntry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)))
        {
            writer.Write("application/epub+zip");
        }

        WriteEntry(
            archive,
            "META-INF/container.xml",
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml" />
              </rootfiles>
            </container>
            """);

        var manifestBuilder = new StringBuilder();
        var spineBuilder = new StringBuilder();
        for (var index = 0; index < chapterItems.Count; index++)
        {
            var item = chapterItems[index];
            var itemId = $"chapter{index + 1}";
            manifestBuilder.AppendLine($"    <item id=\"{itemId}\" href=\"{item.Href}\" media-type=\"application/xhtml+xml\" />");
            spineBuilder.AppendLine($"    <itemref idref=\"{itemId}\" />");
            WriteEntry(archive, $"OPS/{item.Href}", item.Html);
        }

        if (cover is not null)
        {
            manifestBuilder.AppendLine(
                $"    <item id=\"cover-image\" href=\"{cover.Href}\" media-type=\"{cover.MediaType}\" properties=\"cover-image\" />");
            WriteEntry(archive, $"OPS/{cover.Href}", cover.Data);
        }

        WriteEntry(
            archive,
            "OPS/content.opf",
            $$"""
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>{{title}}</dc:title>
                <dc:creator>{{author}}</dc:creator>
              </metadata>
              <manifest>
            {{manifestBuilder.ToString().TrimEnd()}}
              </manifest>
              <spine>
            {{spineBuilder.ToString().TrimEnd()}}
              </spine>
            </package>
            """);

        return filePath;
    }

    private static void WriteEntry(ZipArchive archive, string entryName, string content)
    {
        var entry = archive.CreateEntry(entryName, CompressionLevel.Fastest);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        writer.Write(content);
    }

    private static void WriteEntry(ZipArchive archive, string entryName, byte[] content)
    {
        var entry = archive.CreateEntry(entryName, CompressionLevel.Fastest);
        using var stream = entry.Open();
        stream.Write(content, 0, content.Length);
    }

    private static string HtmlDocument(string title, string body) =>
        $$"""
        <html>
          <head>
            <title>{{title}}</title>
          </head>
          <body>
            <h1>{{title}}</h1>
            <p>{{body}}</p>
          </body>
        </html>
        """;

    private static string LongParagraph(string seed) =>
        string.Join(
            ' ',
            Enumerable.Repeat($"{seed} text for AudioLocal Windows import heuristics testing.", 6));

    private sealed record EpubItem(string Href, string Html);

    private sealed record EpubCover(string Href, string MediaType, byte[] Data);
}
