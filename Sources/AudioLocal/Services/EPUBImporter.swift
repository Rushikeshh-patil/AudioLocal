import AppKit
import Foundation

struct EPUBImporter: Sendable {
    enum ImportError: LocalizedError {
        case unsupportedFormat
        case unzipToolMissing
        case unzipFailed(String)
        case invalidContainer
        case invalidPackage
        case noReadableChapters

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Only EPUB imports are supported right now."
            case .unzipToolMissing:
                return "macOS unzip support is unavailable."
            case let .unzipFailed(message):
                return "Failed to unpack the EPUB: \(message)"
            case .invalidContainer:
                return "The EPUB is missing META-INF/container.xml or a valid rootfile entry."
            case .invalidPackage:
                return "The EPUB package file is invalid or missing."
            case .noReadableChapters:
                return "This EPUB did not contain any readable XHTML chapters."
            }
        }
    }

    func importBook(from sourceURL: URL) throws -> ImportedBook {
        guard sourceURL.pathExtension.lowercased() == "epub" else {
            throw ImportError.unsupportedFormat
        }

        let unzipPath = "/usr/bin/unzip"
        guard FileManager.default.isExecutableFile(atPath: unzipPath) else {
            throw ImportError.unzipToolMissing
        }

        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioLocal-EPUB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: extractionDirectory)
        }

        try unzip(sourceURL: sourceURL, unzipPath: unzipPath, extractionDirectory: extractionDirectory)

        let containerURL = extractionDirectory
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        guard let packageRelativePath = try ContainerParser.parseRootfilePath(at: containerURL) else {
            throw ImportError.invalidContainer
        }

        let packageURL = extractionDirectory
            .appendingPathComponent(packageRelativePath)
            .standardizedFileURL
        let package = try PackageParser.parsePackage(at: packageURL)
        let contentDirectory = packageURL.deletingLastPathComponent()

        var chapters: [ImportedChapter] = []
        for itemRef in package.spineItemRefs {
            guard let item = package.manifest[itemRef] else { continue }
            guard item.isReadableChapter else { continue }

            let href = item.href.components(separatedBy: "#").first ?? item.href
            let chapterURL = contentDirectory.appendingPathComponent(href).standardizedFileURL
            guard let chapterData = try? Data(contentsOf: chapterURL) else { continue }

            let extracted = Self.extractChapter(from: chapterData)
            guard !extracted.text.isEmpty else { continue }

            let title = extracted.title?.nilIfBlank
                ?? package.titleForItem(item, chapterNumber: chapters.count + 1)
            chapters.append(
                ImportedChapter(
                    importOrder: chapters.count + 1,
                    title: title,
                    originalText: extracted.text,
                    sourcePath: item.href
                )
            )
        }

        guard !chapters.isEmpty else {
            throw ImportError.noReadableChapters
        }

        let title = package.bookTitle?.nilIfBlank ?? sourceURL.deletingPathExtension().lastPathComponent
        return ImportedBook(
            title: title,
            author: package.bookAuthor?.nilIfBlank,
            sourceURL: sourceURL,
            chapters: chapters
        )
    }

    private func unzip(sourceURL: URL, unzipPath: String, extractionDirectory: URL) throws {
        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: unzipPath)
        process.arguments = ["-qq", "-o", sourceURL.path, "-d", extractionDirectory.path]
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw ImportError.unzipFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown unzip error"
            throw ImportError.unzipFailed(stderr)
        }
    }

    private static func extractChapter(from data: Data) -> (title: String?, text: String) {
        let htmlString = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let htmlOptions: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let renderedText = (try? NSAttributedString(data: data, options: htmlOptions, documentAttributes: nil).string) ?? htmlString

        return (
            title: extractHeading(from: htmlString),
            text: normalizeRenderedText(renderedText)
        )
    }

    private static func extractHeading(from htmlString: String) -> String? {
        let patterns = [
            "<title[^>]*>(.*?)</title>",
            "<h1[^>]*>(.*?)</h1>",
            "<h2[^>]*>(.*?)</h2>"
        ]

        for pattern in patterns {
            if let value = firstCapture(in: htmlString, pattern: pattern)?.htmlStripped.nilIfBlank {
                return normalizeRenderedText(value)
            }
        }

        return nil
    }

    private static func firstCapture(in string: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[captureRange])
    }

    private static func normalizeRenderedText(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        value = value.replacingOccurrences(
            of: #"[ \t]+\n"#,
            with: "\n",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct EPUBPackage {
    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: Set<String>

        var isReadableChapter: Bool {
            guard !properties.contains("nav") else { return false }
            return mediaType.contains("html") || mediaType.contains("xhtml") || mediaType.contains("xml")
        }
    }

    let bookTitle: String?
    let bookAuthor: String?
    let manifest: [String: ManifestItem]
    let spineItemRefs: [String]

    func titleForItem(_ item: ManifestItem, chapterNumber: Int) -> String {
        let fileStem = URL(fileURLWithPath: item.href).deletingPathExtension().lastPathComponent
        let prettyStem = fileStem
            .replacingOccurrences(of: #"[_\-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let title = prettyStem.nilIfBlank {
            return title.capitalized
        }

        return "Chapter \(chapterNumber)"
    }
}

private enum ContainerParser {
    static func parseRootfilePath(at url: URL) throws -> String? {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBImporter.ImportError.invalidContainer
        }

        let delegate = ContainerParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw EPUBImporter.ImportError.invalidContainer
        }
        return delegate.rootfilePath
    }
}

private final class ContainerParserDelegate: NSObject, XMLParserDelegate {
    var rootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = (qName ?? elementName).split(separator: ":").last.map(String.init) ?? elementName
        guard localName == "rootfile" else { return }
        rootfilePath = attributeDict["full-path"] ?? rootfilePath
    }
}

private enum PackageParser {
    static func parsePackage(at url: URL) throws -> EPUBPackage {
        guard let parser = XMLParser(contentsOf: url) else {
            throw EPUBImporter.ImportError.invalidPackage
        }

        let delegate = PackageParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw EPUBImporter.ImportError.invalidPackage
        }
        return delegate.makePackage()
    }
}

private final class PackageParserDelegate: NSObject, XMLParserDelegate {
    private var manifest: [String: EPUBPackage.ManifestItem] = [:]
    private var spineItemRefs: [String] = []
    private var currentTextElement: String?
    private var currentText = ""
    private(set) var bookTitle: String?
    private(set) var bookAuthor: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = normalized(elementName: qName ?? elementName)
        switch localName {
        case "item":
            guard let id = attributeDict["id"],
                  let href = attributeDict["href"] else { return }
            let mediaType = attributeDict["media-type"] ?? ""
            let properties = Set((attributeDict["properties"] ?? "").split(separator: " ").map(String.init))
            manifest[id] = EPUBPackage.ManifestItem(id: id, href: href, mediaType: mediaType, properties: properties)
        case "itemref":
            if let idRef = attributeDict["idref"] {
                spineItemRefs.append(idRef)
            }
        case "title", "creator":
            currentTextElement = localName
            currentText = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentTextElement != nil else { return }
        currentText.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = normalized(elementName: qName ?? elementName)
        guard localName == currentTextElement else { return }

        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if localName == "title", bookTitle == nil, !value.isEmpty {
            bookTitle = value
        } else if localName == "creator", bookAuthor == nil, !value.isEmpty {
            bookAuthor = value
        }

        currentTextElement = nil
        currentText = ""
    }

    func makePackage() -> EPUBPackage {
        EPUBPackage(
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            manifest: manifest,
            spineItemRefs: spineItemRefs
        )
    }

    private func normalized(elementName: String) -> String {
        (elementName.split(separator: ":").last.map(String.init) ?? elementName).lowercased()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var htmlStripped: String {
        guard let data = data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return self
        }

        return attributed.string
    }
}
