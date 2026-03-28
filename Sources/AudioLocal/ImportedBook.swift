import Foundation

struct ImportedBook: Identifiable {
    let id = UUID()
    var title: String
    var author: String?
    let sourceURL: URL
    var chapters: [ImportedChapter]

    var totalWordCount: Int {
        chapters.reduce(0) { $0 + $1.wordCount }
    }

    var includedChapters: [ImportedChapter] {
        chapters.filter(\.isIncluded)
    }

    var includedWordCount: Int {
        includedChapters.reduce(0) { $0 + $1.wordCount }
    }
}

struct ImportedChapter: Identifiable, Hashable {
    let id: UUID
    let importOrder: Int
    var title: String
    let originalText: String
    var workingText: String
    var isIncluded: Bool
    let sourcePath: String

    init(
        id: UUID = UUID(),
        importOrder: Int,
        title: String,
        originalText: String,
        workingText: String? = nil,
        isIncluded: Bool = true,
        sourcePath: String
    ) {
        self.id = id
        self.importOrder = importOrder
        self.title = title
        self.originalText = originalText
        self.workingText = workingText ?? originalText
        self.isIncluded = isIncluded
        self.sourcePath = sourcePath
    }

    var wordCount: Int {
        workingText.split { $0.isWhitespace || $0.isNewline }.count
    }

    var hasEdits: Bool {
        workingText != originalText
    }
}
