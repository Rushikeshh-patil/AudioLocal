import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    enum ProviderMode: String, CaseIterable, Identifiable {
        case localOnly = "kokoroOnly"
        case automatic
        case geminiOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .localOnly:
                return "Local only"
            case .automatic:
                return "Automatic"
            case .geminiOnly:
                return "Gemini only"
            }
        }
    }

    enum LocalModel: String, CaseIterable, Identifiable {
        case kokoro
        case voxtralMLX

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kokoro:
                return "Kokoro"
            case .voxtralMLX:
                return "Voxtral MLX"
            }
        }

        var detail: String {
            switch self {
            case .kokoro:
                return "Fast, bundled-friendly local TTS with lightweight voices and optional GPU acceleration through PyTorch MPS."
            case .voxtralMLX:
                return "Experimental multilingual local TTS through MLX on Apple Silicon. Expect a larger runtime and slower model startup than Kokoro."
            }
        }
    }

    enum SaveLocationMode: String, CaseIterable, Identifiable {
        case managedInbox
        case customFolder

        var id: String { rawValue }

        var title: String {
            switch self {
            case .managedInbox:
                return "Audiobookshelf Inbox"
            case .customFolder:
                return "Custom folder"
            }
        }
    }

    enum ChapterFilterMode: String, CaseIterable, Identifiable {
        case all
        case included
        case excluded

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "All"
            case .included:
                return "Included"
            case .excluded:
                return "Excluded"
            }
        }
    }

    @Published var articleTitle: String {
        didSet {
            defaults.set(articleTitle, forKey: Keys.articleTitle)
            importedBook?.title = articleTitle
        }
    }

    @Published var articleBody: String {
        didSet {
            defaults.set(articleBody, forKey: Keys.articleBody)
            syncSelectedChapterTextFromEditor()
        }
    }

    @Published var providerMode: ProviderMode {
        didSet { defaults.set(providerMode.rawValue, forKey: Keys.providerMode) }
    }

    @Published var localModel: LocalModel {
        didSet { defaults.set(localModel.rawValue, forKey: Keys.localModel) }
    }

    @Published var geminiAPIKey: String {
        didSet { saveAPIKey(geminiAPIKey) }
    }

    @Published var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: Keys.geminiModel) }
    }

    @Published var geminiVoice: String {
        didSet { defaults.set(geminiVoice, forKey: Keys.geminiVoice) }
    }

    @Published var kokoroPythonPath: String {
        didSet { defaults.set(kokoroPythonPath, forKey: Keys.kokoroPythonPath) }
    }

    @Published var kokoroVoice: String {
        didSet { defaults.set(kokoroVoice, forKey: Keys.kokoroVoice) }
    }

    @Published var kokoroSpeed: Double {
        didSet { defaults.set(kokoroSpeed, forKey: Keys.kokoroSpeed) }
    }

    @Published var voxtralPythonPath: String {
        didSet { defaults.set(voxtralPythonPath, forKey: Keys.voxtralPythonPath) }
    }

    @Published var voxtralModel: String {
        didSet { defaults.set(voxtralModel, forKey: Keys.voxtralModel) }
    }

    @Published var voxtralVoice: String {
        didSet { defaults.set(voxtralVoice, forKey: Keys.voxtralVoice) }
    }

    @Published var saveLocationMode: SaveLocationMode {
        didSet { defaults.set(saveLocationMode.rawValue, forKey: Keys.saveLocationMode) }
    }

    @Published var exportFormat: AudioExportFormat {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    @Published var customSaveDirectory: String {
        didSet { defaults.set(customSaveDirectory, forKey: Keys.customSaveDirectory) }
    }

    @Published var statusMessage = "Ready"
    @Published var lastSavedPath = ""
    @Published var lastBackend = ""
    @Published var lastLocalDevice = ""
    @Published var isGenerating = false
    @Published var isImportingBook = false
    @Published var chapterSearchQuery = "" {
        didSet { reconcileSelectedImportedChapterVisibility() }
    }
    @Published var chapterFilterMode: ChapterFilterMode = .all {
        didSet { reconcileSelectedImportedChapterVisibility() }
    }
    @Published var isSettingsInspectorVisible = true
    @Published var generationProgress = 0.0
    @Published var progressTitle = ""
    @Published var progressDetail = ""
    @Published private(set) var importedBook: ImportedBook?
    @Published var selectedImportedChapterID: ImportedChapter.ID? {
        didSet { applySelectedImportedChapterToEditor() }
    }

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.rushikeshpatil.AudioLocal")
    private let geminiClient = GeminiTTSClient()
    private let kokoroSynthesizer = KokoroSynthesizer()
    private let voxtralSynthesizer = VoxtralMLXSynthesizer()
    private let storageCoordinator = AudioStorageCoordinator()
    private let epubImporter = EPUBImporter()
    private let wavStitcher = WAVStitcher()
    private var progressTickerTask: Task<Void, Never>?
    private var currentGenerationPhase: GenerationPhase = .preparing
    private var generationEstimate = GenerationEstimate(preparing: 1.0, synthesizing: 8.0, saving: 2.0)
    private var phaseStartDate = Date.now
    private var lastLocalModelUsed: LocalModel?
    private var isApplyingImportedChapterSelection = false

    private enum Keys {
        static let articleTitle = "draft.articleTitle"
        static let articleBody = "draft.articleBody"
        static let providerMode = "settings.providerMode"
        static let localModel = "settings.localModel"
        static let geminiModel = "settings.geminiModel"
        static let geminiVoice = "settings.geminiVoice"
        static let kokoroPythonPath = "settings.kokoroPythonPath"
        static let kokoroVoice = "settings.kokoroVoice"
        static let kokoroSpeed = "settings.kokoroSpeed"
        static let voxtralPythonPath = "settings.voxtralPythonPath"
        static let voxtralModel = "settings.voxtralModel"
        static let voxtralVoice = "settings.voxtralVoice"
        static let saveLocationMode = "settings.saveLocationMode"
        static let exportFormat = "settings.exportFormat"
        static let customSaveDirectory = "settings.customSaveDirectory"
    }

    private static let supportsVoxtralMLX: Bool = {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }()

    init() {
        articleTitle = defaults.string(forKey: Keys.articleTitle) ?? ""
        articleBody = defaults.string(forKey: Keys.articleBody) ?? ""
        providerMode = ProviderMode(rawValue: defaults.string(forKey: Keys.providerMode) ?? "") ?? .localOnly

        let savedLocalModel = LocalModel(rawValue: defaults.string(forKey: Keys.localModel) ?? "") ?? .kokoro
        localModel = Self.supportsVoxtralMLX ? savedLocalModel : .kokoro

        geminiAPIKey = (try? keychain.read(account: "gemini_api_key")) ?? ""
        geminiModel = defaults.string(forKey: Keys.geminiModel) ?? "gemini-2.5-flash-preview-tts"
        geminiVoice = defaults.string(forKey: Keys.geminiVoice) ?? "Kore"

        kokoroPythonPath = Self.resolveKokoroPythonPath(defaults: defaults, bundle: .main)
        kokoroVoice = defaults.string(forKey: Keys.kokoroVoice) ?? "af_heart"
        let storedSpeed = defaults.object(forKey: Keys.kokoroSpeed) as? Double
        kokoroSpeed = storedSpeed ?? 1.0

        voxtralPythonPath = Self.resolveVoxtralPythonPath(defaults: defaults, bundle: .main)
        voxtralModel = defaults.string(forKey: Keys.voxtralModel) ?? VoxtralMLXSynthesizer.defaultModelID
        voxtralVoice = defaults.string(forKey: Keys.voxtralVoice) ?? "casual_male"

        saveLocationMode = SaveLocationMode(rawValue: defaults.string(forKey: Keys.saveLocationMode) ?? "") ?? .managedInbox
        exportFormat = AudioExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? "") ?? .m4b
        customSaveDirectory = defaults.string(forKey: Keys.customSaveDirectory) ?? ""
    }

    var shouldShowProgress: Bool {
        isGenerating || generationProgress > 0
    }

    var usesLocalEngineInCurrentMode: Bool {
        providerMode != .geminiOnly
    }

    var isVoxtralAvailableOnCurrentMac: Bool {
        Self.supportsVoxtralMLX
    }

    var providerModeDetail: String {
        switch providerMode {
        case .localOnly:
            return "Use the selected local engine only. No Gemini API key is required."
        case .automatic:
            return "Use \(localModel.title) first. If it fails and a Gemini API key is configured, fall back to Gemini."
        case .geminiOnly:
            return "Use Gemini and fail on any Gemini error."
        }
    }

    var selectedLocalModelDetail: String {
        localModel.detail
    }

    var localModelFootnote: String? {
        if localModel == .voxtralMLX && !isVoxtralAvailableOnCurrentMac {
            return "Voxtral MLX is only available in Apple Silicon builds of AudioLocal."
        }

        if localModel == .voxtralMLX {
            return "The default MLX model is about 8 GB and is best suited for Apple Silicon Macs with extra memory headroom. If generation fails, the upstream mlx-audio runtime may still be missing the Voxtral TTS loader."
        }

        return nil
    }

    var isLocalGPUActive: Bool {
        let device = lastLocalDevice.uppercased()
        return device == "MPS" || device == "CUDA" || device == "MLX" || device.contains("GPU")
    }

    var localDeviceBadgeText: String {
        let localEngine = lastLocalModelUsed ?? localModel

        if lastLocalDevice.isEmpty {
            switch localEngine {
            case .kokoro:
                return "Kokoro device: auto"
            case .voxtralMLX:
                return "Voxtral MLX: auto"
            }
        }

        return isLocalGPUActive ? "\(localEngine.title): \(lastLocalDevice)" : "\(localEngine.title): \(lastLocalDevice)"
    }

    var localDeviceDetail: String {
        let localEngine = lastLocalModelUsed ?? localModel

        switch localEngine {
        case .kokoro:
            if lastLocalDevice.isEmpty {
                return "Waiting for the first Kokoro run. The runtime will prefer MPS, then fall back to CPU if needed."
            }

            return isLocalGPUActive
                ? "\(lastLocalDevice) acceleration is active for the last Kokoro generation."
                : "\(lastLocalDevice) is active for the last Kokoro generation."
        case .voxtralMLX:
            if !isVoxtralAvailableOnCurrentMac {
                return "Voxtral MLX requires Apple Silicon."
            }

            if lastLocalDevice.isEmpty {
                return "Waiting for the first Voxtral run. MLX uses Apple Silicon acceleration for local generation."
            }

            return "\(lastLocalDevice) acceleration is active for the last Voxtral MLX generation."
        }
    }

    var hasImportedBook: Bool {
        importedBook != nil
    }

    var isBookWorkspaceMode: Bool {
        hasImportedBook
    }

    var importedBookAuthorName: String? {
        importedBook?.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var importedBookSummary: String {
        guard let importedBook else {
            return "Import an EPUB to browse chapters, reorder them, and build a stitched audiobook."
        }

        let authorDetail = importedBookAuthorName.map { " by \($0)" } ?? ""
        return "\(importedBook.chapters.count) chapters, \(Self.formatWordCount(importedBook.totalWordCount))\(authorDetail)"
    }

    var importedBookOrganizerSummary: String {
        guard let importedBook else {
            return "No EPUB selected"
        }

        return "\(includedImportedChapterCount) of \(importedBook.chapters.count) included • \(Self.formatWordCount(importedBook.includedWordCount))"
    }

    var importedBookSourceName: String {
        importedBook?.sourceURL.lastPathComponent ?? "No EPUB selected"
    }

    var importButtonTitle: String {
        importedBook == nil ? "Import EPUB..." : "Replace EPUB..."
    }

    var generateSingleButtonTitle: String {
        isBookWorkspaceMode ? "Export Selected Chapter" : "Create Audio File"
    }

    var generateFullAudiobookTitle: String {
        "Create Full Audiobook"
    }

    var selectedImportedChapter: ImportedChapter? {
        guard let importedBook, let selectedImportedChapterID else {
            return nil
        }
        return importedBook.chapters.first(where: { $0.id == selectedImportedChapterID })
    }

    var selectedImportedChapterPosition: Int? {
        guard let importedBook, let selectedImportedChapterID,
              let index = importedBook.chapters.firstIndex(where: { $0.id == selectedImportedChapterID }) else {
            return nil
        }
        return index + 1
    }

    var selectedImportedChapterTitle: String {
        selectedImportedChapter?.title ?? "Select a chapter"
    }

    var selectedImportedChapterDetail: String {
        guard let selectedImportedChapter, let position = selectedImportedChapterPosition else {
            return "Choose a chapter to review or edit its imported text."
        }

        let includedState = selectedImportedChapter.isIncluded ? "Included" : "Excluded"
        return "Chapter \(position) • \(includedState) • \(Self.formatWordCount(selectedImportedChapter.wordCount))"
    }

    var selectedImportedChapterHasEdits: Bool {
        selectedImportedChapter?.hasEdits == true
    }

    var canRevertSelectedImportedChapter: Bool {
        selectedImportedChapterHasEdits
    }

    var includedImportedChapterCount: Int {
        importedBook?.includedChapters.count ?? 0
    }

    var visibleImportedChapters: [ImportedChapter] {
        guard let importedBook else { return [] }

        let query = trimmedChapterSearchQuery.lowercased()
        return importedBook.chapters.filter { chapter in
            let matchesFilter: Bool
            switch chapterFilterMode {
            case .all:
                matchesFilter = true
            case .included:
                matchesFilter = chapter.isIncluded
            case .excluded:
                matchesFilter = !chapter.isIncluded
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            let haystack = "\(chapter.title)\n\(chapter.workingText)".lowercased()
            return haystack.contains(query)
        }
    }

    var visibleImportedChapterCount: Int {
        visibleImportedChapters.count
    }

    var chapterListStatusText: String {
        if trimmedChapterSearchQuery.isEmpty {
            return importedBookOrganizerSummary
        }

        return "\(visibleImportedChapterCount) matches • \(includedImportedChapterCount) included"
    }

    var canDragReorderImportedChapters: Bool {
        hasImportedBook && chapterFilterMode == .all && trimmedChapterSearchQuery.isEmpty
    }

    var canMoveSelectedImportedChapterUp: Bool {
        guard let currentIndex = selectedImportedChapterPosition else { return false }
        return currentIndex > 1
    }

    var canMoveSelectedImportedChapterDown: Bool {
        guard let currentIndex = selectedImportedChapterPosition, let importedBook else { return false }
        return currentIndex < importedBook.chapters.count
    }

    var canResetImportedChapterOrder: Bool {
        guard let importedBook else { return false }
        return importedBook.chapters.enumerated().contains { offset, chapter in
            chapter.importOrder != offset + 1
        }
    }

    var bookWorkspaceSettingsButtonTitle: String {
        isSettingsInspectorVisible ? "Hide Settings" : "Show Settings"
    }

    var footerSaveSummary: String {
        let locationTitle = saveLocationMode == .managedInbox ? "Audiobookshelf Inbox" : "Custom folder"
        return "\(locationTitle) • \(exportFormat.title)"
    }

    var footerSelectionSummary: String {
        if isBookWorkspaceMode {
            return "\(includedImportedChapterCount) chapters selected"
        }

        return "\(articleBody.count) characters"
    }

    var canGenerate: Bool {
        !articleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !articleBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isSaveLocationConfigured &&
        (!isBookWorkspaceMode || selectedImportedChapter != nil)
    }

    var canGenerateFullAudiobook: Bool {
        includedImportedChapterCount > 0 && isSaveLocationConfigured
    }

    var isSaveLocationConfigured: Bool {
        switch saveLocationMode {
        case .managedInbox:
            return true
        case .customFolder:
            return !trimmedCustomSaveDirectory.isEmpty
        }
    }

    var customSaveDirectoryDisplay: String {
        let trimmedPath = trimmedCustomSaveDirectory
        return trimmedPath.isEmpty ? "No custom folder selected yet." : trimmedPath
    }

    var saveLocationButtonTitle: String {
        trimmedCustomSaveDirectory.isEmpty ? "Choose Folder..." : "Change Folder..."
    }

    var saveLocationPreview: String {
        switch saveLocationMode {
        case .managedInbox:
            return "\(VolumeManager.inboxRootPath)/<title-timestamp>/<title-timestamp>.\(exportFormat.filenameExtension)"
        case .customFolder:
            let basePath = trimmedCustomSaveDirectory
            guard !basePath.isEmpty else {
                return "Choose a folder to save generated audio."
            }
            return "\(basePath)/<title-timestamp>/<title-timestamp>.\(exportFormat.filenameExtension)"
        }
    }

    var saveLocationDetail: String {
        switch saveLocationMode {
        case .managedInbox:
            return "Staged locally, \(exportFormat.processingDescription), then copied to the SMB Audiobookshelf Inbox. The app will try to mount \(VolumeManager.shareURLString) if needed."
        case .customFolder:
            return "Staged locally, \(exportFormat.processingDescription), then copied into the folder you choose. Each export still gets its own subfolder."
        }
    }

    func generateAudio() async {
        guard canGenerate else {
            if !isSaveLocationConfigured {
                statusMessage = "Choose a save location before generating audio."
            } else if isBookWorkspaceMode {
                statusMessage = "Select a chapter with text before exporting audio."
            } else {
                statusMessage = "Enter both a title and article text."
            }
            return
        }

        isGenerating = true
        lastSavedPath = ""
        lastBackend = ""
        lastLocalDevice = ""
        lastLocalModelUsed = nil
        startProgressTracking()

        defer {
            isGenerating = false
            stopProgressTicker()
        }

        do {
            let itemName = makeItemName(from: singleExportTitle)
            let destination = try selectedStorageDestination()
            let result: GeneratedAudio
            let exportText = selectedImportedChapter?.workingText ?? articleBody

            transitionProgress(to: .synthesizing)

            result = try await synthesizeText(exportText)

            transitionProgress(to: .saving)
            statusMessage = saveLocationMode == .managedInbox
                ? "Compressing and copying audio to Audiobookshelf Inbox..."
                : "Compressing and saving audio to the selected folder..."
            let outputURL = try await storageCoordinator.saveAudio(
                result.wavData,
                itemName: itemName,
                destination: destination,
                format: exportFormat
            )
            lastSavedPath = outputURL.path
            lastBackend = result.backend
            statusMessage = "Saved \(outputURL.lastPathComponent) via \(result.backend)."
            completeProgressTracking(with: outputURL)
        } catch {
            resetProgressTracking()
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func generateFullAudiobook() async {
        guard let importedBook else {
            statusMessage = "Import an EPUB before creating a full audiobook."
            return
        }

        let includedChapters = importedBook.includedChapters
        guard !includedChapters.isEmpty else {
            statusMessage = "Select at least one chapter for the final audiobook."
            return
        }

        guard isSaveLocationConfigured else {
            statusMessage = "Choose a save location before generating audio."
            return
        }

        isGenerating = true
        lastSavedPath = ""
        lastBackend = ""
        lastLocalDevice = ""
        lastLocalModelUsed = nil
        stopProgressTicker()
        setManualProgress(title: "Preparing book", detail: "\(includedChapters.count) selected chapters queued", progress: 0.03)

        defer {
            isGenerating = false
            stopProgressTicker()
        }

        do {
            let destination = try selectedStorageDestination()
            var chapterAudio: [Data] = []
            var usedBackends: [String] = []
            let totalChapters = includedChapters.count

            for (offset, chapter) in includedChapters.enumerated() {
                let progressStart = 0.05 + (0.72 * (Double(offset) / Double(totalChapters)))
                let progressEnd = 0.05 + (0.72 * (Double(offset + 1) / Double(totalChapters)))

                setManualProgress(
                    title: "Generating chapter \(offset + 1) of \(totalChapters)",
                    detail: chapter.title,
                    progress: progressStart
                )
                statusMessage = "Generating chapter \(offset + 1) of \(totalChapters): \(chapter.title)"

                let result = try await synthesizeText(chapter.workingText)
                chapterAudio.append(result.wavData)
                usedBackends.append(result.backend)

                setManualProgress(
                    title: "Generating chapter \(offset + 1) of \(totalChapters)",
                    detail: "Finished \(chapter.title)",
                    progress: progressEnd
                )
            }

            setManualProgress(title: "Stitching chapters", detail: "Combining chapter audio into one book", progress: 0.84)
            let stitchedBook = try wavStitcher.stitch(chapterAudio: chapterAudio)

            setManualProgress(title: "Saving audiobook", detail: "Compressing and copying the final file", progress: 0.93)
            let itemName = makeItemName(from: articleTitle)
            let outputURL = try await storageCoordinator.saveAudio(
                stitchedBook,
                itemName: itemName,
                destination: destination,
                format: exportFormat
            )

            lastSavedPath = outputURL.path
            lastBackend = summarizeBackends(usedBackends)
            statusMessage = "Saved \(outputURL.lastPathComponent) from \(totalChapters) selected chapters."
            completeProgressTracking(with: outputURL)
        } catch {
            resetProgressTracking()
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func revealLastFile() {
        guard !lastSavedPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastSavedPath)])
    }

    func chooseCustomSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose a save folder"
        panel.message = "AudioLocal will create a new subfolder inside this location for each generated item."
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = initialCustomFolderURL()

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        customSaveDirectory = selectedURL.standardizedFileURL.path
        saveLocationMode = .customFolder
        statusMessage = "Custom save folder updated."
    }

    func importEPUB() {
        let panel = NSOpenPanel()
        panel.title = "Import EPUB"
        panel.message = "Choose an EPUB book to split into chapters for reading and audiobook creation."
        panel.prompt = "Import Book"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let epubType = UTType(filenameExtension: "epub") {
            panel.allowedContentTypes = [epubType]
        }
        panel.directoryURL = importedBook?.sourceURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        Task {
            await importBook(from: selectedURL)
        }
    }

    func clearImportedBook() {
        importedBook = nil
        selectedImportedChapterID = nil
        chapterSearchQuery = ""
        chapterFilterMode = .all
        isSettingsInspectorVisible = true
        statusMessage = "Removed imported EPUB. The current text stays in the editor."
    }

    func selectImportedChapter(_ chapterID: ImportedChapter.ID) {
        selectedImportedChapterID = chapterID
    }

    func toggleImportedChapterInclusion(_ chapterID: ImportedChapter.ID) {
        setImportedChapter(chapterID, included: chapterInclusionState(for: chapterID) == false)
    }

    func setImportedChapter(_ chapterID: ImportedChapter.ID, included: Bool) {
        guard var importedBook,
              let index = importedBook.chapters.firstIndex(where: { $0.id == chapterID }) else {
            return
        }

        importedBook.chapters[index].isIncluded = included
        self.importedBook = importedBook
        reconcileSelectedImportedChapterVisibility()
    }

    func selectAllImportedChapters() {
        guard var importedBook else { return }
        for index in importedBook.chapters.indices {
            importedBook.chapters[index].isIncluded = true
        }
        self.importedBook = importedBook
        reconcileSelectedImportedChapterVisibility()
    }

    func selectNoImportedChapters() {
        guard var importedBook else { return }
        for index in importedBook.chapters.indices {
            importedBook.chapters[index].isIncluded = false
        }
        self.importedBook = importedBook
        reconcileSelectedImportedChapterVisibility()
    }

    func toggleSettingsInspector() {
        isSettingsInspectorVisible.toggle()
    }

    func moveSelectedImportedChapterUp() {
        moveSelectedImportedChapter(by: -1)
    }

    func moveSelectedImportedChapterDown() {
        moveSelectedImportedChapter(by: 1)
    }

    func moveSelectedImportedChapterToTop() {
        moveSelectedImportedChapter(to: 0)
    }

    func moveSelectedImportedChapterToBottom() {
        guard let importedBook else { return }
        moveSelectedImportedChapter(to: importedBook.chapters.count - 1)
    }

    func reorderImportedChapters(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard canDragReorderImportedChapters, var importedBook else {
            return
        }

        Self.moveChapters(&importedBook.chapters, fromOffsets: offsets, toOffset: destination)
        self.importedBook = importedBook
    }

    func moveImportedChapter(_ chapterID: ImportedChapter.ID, to targetChapterID: ImportedChapter.ID) {
        guard canDragReorderImportedChapters, var importedBook,
              let sourceIndex = importedBook.chapters.firstIndex(where: { $0.id == chapterID }),
              let targetIndex = importedBook.chapters.firstIndex(where: { $0.id == targetChapterID }),
              sourceIndex != targetIndex else {
            return
        }

        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        Self.moveChapters(&importedBook.chapters, fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        self.importedBook = importedBook
    }

    func resetImportedChapterOrder() {
        guard var importedBook else { return }
        importedBook.chapters.sort { $0.importOrder < $1.importOrder }
        self.importedBook = importedBook
        reconcileSelectedImportedChapterVisibility()
    }

    func revertSelectedImportedChapterText() {
        guard let selectedImportedChapterID,
              var importedBook,
              let index = importedBook.chapters.firstIndex(where: { $0.id == selectedImportedChapterID }) else {
            return
        }

        importedBook.chapters[index].workingText = importedBook.chapters[index].originalText
        self.importedBook = importedBook
        applySelectedImportedChapterToEditor()
    }

    private func importBook(from url: URL) async {
        isImportingBook = true
        statusMessage = "Importing \(url.lastPathComponent)..."

        defer {
            isImportingBook = false
        }

        do {
            let importer = epubImporter
            let importedBook = try await Task.detached(priority: .userInitiated) {
                try importer.importBook(from: url)
            }.value

            self.importedBook = importedBook
            chapterSearchQuery = ""
            chapterFilterMode = .all
            isSettingsInspectorVisible = true
            articleTitle = importedBook.title
            selectedImportedChapterID = importedBook.chapters.first?.id
            statusMessage = "Imported \(importedBook.title) with \(importedBook.chapters.count) chapters."
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applySelectedImportedChapterToEditor() {
        guard let importedBook, let selectedImportedChapterID else {
            return
        }

        guard let chapter = importedBook.chapters.first(where: { $0.id == selectedImportedChapterID }) else {
            return
        }

        isApplyingImportedChapterSelection = true
        articleBody = chapter.workingText
        isApplyingImportedChapterSelection = false
    }

    private func syncSelectedChapterTextFromEditor() {
        guard !isApplyingImportedChapterSelection,
              let selectedImportedChapterID,
              var importedBook,
              let index = importedBook.chapters.firstIndex(where: { $0.id == selectedImportedChapterID }) else {
            return
        }

        importedBook.chapters[index].workingText = articleBody
        self.importedBook = importedBook
    }

    private func chapterInclusionState(for chapterID: ImportedChapter.ID) -> Bool? {
        importedBook?.chapters.first(where: { $0.id == chapterID })?.isIncluded
    }

    private func moveSelectedImportedChapter(by delta: Int) {
        guard let importedBook,
              let currentIndex = selectedImportedChapterPosition.map({ $0 - 1 }) else {
            return
        }

        moveSelectedImportedChapter(to: max(0, min(importedBook.chapters.count - 1, currentIndex + delta)))
    }

    private func moveSelectedImportedChapter(to destination: Int) {
        guard var importedBook,
              let selectedImportedChapterID,
              let currentIndex = importedBook.chapters.firstIndex(where: { $0.id == selectedImportedChapterID }),
              currentIndex != destination,
              destination >= 0,
              destination < importedBook.chapters.count else {
            return
        }

        let chapter = importedBook.chapters.remove(at: currentIndex)
        importedBook.chapters.insert(chapter, at: destination)
        self.importedBook = importedBook
        reconcileSelectedImportedChapterVisibility()
    }

    private func reconcileSelectedImportedChapterVisibility() {
        guard hasImportedBook else { return }

        let visibleChapterIDs = Set(visibleImportedChapters.map(\.id))
        guard !visibleChapterIDs.isEmpty else {
            selectedImportedChapterID = nil
            return
        }

        if let selectedImportedChapterID, visibleChapterIDs.contains(selectedImportedChapterID) {
            return
        }

        selectedImportedChapterID = visibleImportedChapters.first?.id
    }

    private static func moveChapters(
        _ chapters: inout [ImportedChapter],
        fromOffsets offsets: IndexSet,
        toOffset destination: Int
    ) {
        let movingChapters = offsets.map { chapters[$0] }
        let removedBeforeDestination = offsets.filter { $0 < destination }.count

        for index in offsets.sorted(by: >) {
            chapters.remove(at: index)
        }

        let adjustedDestination = max(0, min(chapters.count, destination - removedBeforeDestination))
        chapters.insert(contentsOf: movingChapters, at: adjustedDestination)
    }

    private struct GeneratedAudio {
        let wavData: Data
        let backend: String
    }

    private enum GenerationPhase {
        case preparing
        case synthesizing
        case saving

        var title: String {
            switch self {
            case .preparing:
                return "Preparing"
            case .synthesizing:
                return "Generating audio"
            case .saving:
                return "Saving file"
            }
        }
    }

    private struct GenerationEstimate {
        let preparing: TimeInterval
        let synthesizing: TimeInterval
        let saving: TimeInterval

        func duration(for phase: GenerationPhase) -> TimeInterval {
            switch phase {
            case .preparing:
                return preparing
            case .synthesizing:
                return synthesizing
            case .saving:
                return saving
            }
        }

        func progressRange(for phase: GenerationPhase) -> ClosedRange<Double> {
            switch phase {
            case .preparing:
                return 0.02...0.08
            case .synthesizing:
                return 0.08...0.84
            case .saving:
                return 0.84...0.98
            }
        }

        func remainingTime(after elapsed: TimeInterval, in phase: GenerationPhase) -> TimeInterval {
            let remainingCurrent = max(duration(for: phase) - elapsed, 0)

            switch phase {
            case .preparing:
                return remainingCurrent + synthesizing + saving
            case .synthesizing:
                return remainingCurrent + saving
            case .saving:
                return remainingCurrent
            }
        }
    }

    private func synthesizeText(_ text: String) async throws -> GeneratedAudio {
        switch providerMode {
        case .automatic:
            return try await synthesizeAutomatically(text: text)
        case .geminiOnly:
            return try await synthesizeWithGemini(text: text)
        case .localOnly:
            return try await synthesizeWithSelectedLocalModel(text: text)
        }
    }

    private func synthesizeAutomatically(text: String) async throws -> GeneratedAudio {
        do {
            return try await synthesizeWithSelectedLocalModel(text: text)
        } catch {
            guard !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw error
            }

            statusMessage = "\(localModel.title) unavailable for this request. Falling back to Gemini..."
            return try await synthesizeWithGemini(text: text)
        }
    }

    private func synthesizeWithSelectedLocalModel(text: String) async throws -> GeneratedAudio {
        switch localModel {
        case .kokoro:
            return try await synthesizeWithKokoro(text: text)
        case .voxtralMLX:
            return try await synthesizeWithVoxtralMLX(text: text)
        }
    }

    private func synthesizeWithGemini(text: String) async throws -> GeneratedAudio {
        statusMessage = "Generating audio with Gemini..."
        let result = try await geminiClient.synthesize(
            text: text,
            apiKey: geminiAPIKey,
            model: geminiModel,
            voiceName: geminiVoice
        )
        let wavData = try WAVEncoder.wrapIfNeeded(audioData: result.audioData, mimeType: result.mimeType)
        return GeneratedAudio(wavData: wavData, backend: "Gemini")
    }

    private func synthesizeWithKokoro(text: String) async throws -> GeneratedAudio {
        statusMessage = "Generating audio with Kokoro..."
        let result = try await kokoroSynthesizer.synthesize(
            text: text,
            pythonExecutable: kokoroPythonPath,
            voice: kokoroVoice,
            speed: kokoroSpeed
        )
        let device = result.device?.uppercased() ?? "CPU"
        lastLocalDevice = device
        lastLocalModelUsed = .kokoro
        return GeneratedAudio(wavData: result.audioData, backend: "Kokoro (\(device))")
    }

    private func synthesizeWithVoxtralMLX(text: String) async throws -> GeneratedAudio {
        guard isVoxtralAvailableOnCurrentMac else {
            throw VoxtralMLXSynthesizer.SynthError.unsupportedPlatform
        }

        statusMessage = "Generating audio with Voxtral MLX..."
        let result = try await voxtralSynthesizer.synthesize(
            text: text,
            pythonExecutable: voxtralPythonPath,
            model: voxtralModel,
            voice: voxtralVoice
        )
        let device = result.device?.uppercased() ?? "MLX"
        lastLocalDevice = device
        lastLocalModelUsed = .voxtralMLX
        return GeneratedAudio(wavData: result.audioData, backend: "Voxtral MLX (\(device))")
    }

    private var singleExportTitle: String {
        if let selectedImportedChapter, let selectedImportedChapterPosition {
            return "\(articleTitle) chapter \(selectedImportedChapterPosition) \(selectedImportedChapter.title)"
        }

        return articleTitle
    }

    private func makeItemName(from rawTitle: String) -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: .now)
        return "\(safeTitle.isEmpty ? "article" : safeTitle)-\(timestamp)"
    }

    private func startProgressTracking() {
        progressTickerTask?.cancel()
        generationEstimate = estimateGenerationDuration()
        currentGenerationPhase = .preparing
        phaseStartDate = .now
        generationProgress = generationEstimate.progressRange(for: .preparing).lowerBound
        progressTitle = GenerationPhase.preparing.title
        progressDetail = "About \(Self.formatDuration(generationEstimate.preparing + generationEstimate.synthesizing + generationEstimate.saving)) remaining"
        refreshProgressTracking()

        progressTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refreshProgressTracking()
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func transitionProgress(to phase: GenerationPhase) {
        currentGenerationPhase = phase
        phaseStartDate = .now
        generationProgress = max(generationProgress, generationEstimate.progressRange(for: phase).lowerBound)
        progressTitle = phase.title
        refreshProgressTracking()
    }

    private func completeProgressTracking(with outputURL: URL) {
        generationProgress = 1.0
        progressTitle = "Completed"
        progressDetail = "Saved \(outputURL.lastPathComponent)"
    }

    private func resetProgressTracking() {
        generationProgress = 0.0
        progressTitle = ""
        progressDetail = ""
    }

    private func setManualProgress(title: String, detail: String, progress: Double) {
        generationProgress = progress
        progressTitle = title
        progressDetail = detail
    }

    private func stopProgressTicker() {
        progressTickerTask?.cancel()
        progressTickerTask = nil
    }

    private func refreshProgressTracking() {
        let elapsed = max(Date.now.timeIntervalSince(phaseStartDate), 0)
        let phaseRange = generationEstimate.progressRange(for: currentGenerationPhase)
        let phaseDuration = max(generationEstimate.duration(for: currentGenerationPhase), 0.5)
        let phaseFraction = min(elapsed / phaseDuration, 0.95)
        let trackedProgress = phaseRange.lowerBound + ((phaseRange.upperBound - phaseRange.lowerBound) * phaseFraction)
        generationProgress = max(generationProgress, trackedProgress)
        progressTitle = currentGenerationPhase.title

        let remainingTime = generationEstimate.remainingTime(after: elapsed, in: currentGenerationPhase)
        progressDetail = remainingTime > 1
            ? "About \(Self.formatDuration(remainingTime)) remaining"
            : "Finishing up..."
    }

    private func estimateGenerationDuration() -> GenerationEstimate {
        let characterCount = max(articleBody.count, 1)

        let synthesisBase: TimeInterval
        switch providerMode {
        case .localOnly, .automatic:
            switch localModel {
            case .kokoro:
                let speedFactor = max(0.75, 1.15 - ((kokoroSpeed - 1.0) * 0.65))
                synthesisBase = (4.5 + (Double(characterCount) * 0.0024)) * speedFactor
            case .voxtralMLX:
                synthesisBase = 9.0 + (Double(characterCount) * 0.0036)
            }
        case .geminiOnly:
            synthesisBase = 3.0 + (Double(characterCount) * 0.0012)
        }

        let saveBase: TimeInterval = saveLocationMode == .managedInbox ? 4.0 : 1.25
        let formatMultiplier: Double
        switch exportFormat {
        case .m4b:
            formatMultiplier = 1.15
        case .m4a:
            formatMultiplier = 1.0
        case .wav:
            formatMultiplier = saveLocationMode == .managedInbox ? 2.8 : 1.35
        }

        let preparing = 0.8
        let synthesizing = min(max(synthesisBase, 4.0), 360.0)
        let saving = min(max((saveBase + (Double(characterCount) / 18000.0)) * formatMultiplier, 1.0), 120.0)
        return GenerationEstimate(preparing: preparing, synthesizing: synthesizing, saving: saving)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let rounded = max(Int(duration.rounded()), 1)
        if rounded < 60 {
            return "\(rounded)s"
        }

        let minutes = rounded / 60
        let seconds = rounded % 60
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }

    private static func formatWordCount(_ count: Int) -> String {
        if count >= 1_000 {
            let rounded = Double(count) / 1_000
            return String(format: "%.1fk words", rounded)
        }

        return "\(count) words"
    }

    private func summarizeBackends(_ backends: [String]) -> String {
        var unique: [String] = []
        for backend in backends where !unique.contains(backend) {
            unique.append(backend)
        }

        if unique.count <= 2 {
            return unique.joined(separator: ", ")
        }

        return "\(unique.count) engines"
    }

    private func saveAPIKey(_ value: String) {
        do {
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychain.delete(account: "gemini_api_key")
            } else {
                try keychain.save(value, account: "gemini_api_key")
            }
        } catch {
            statusMessage = "Failed to store the Gemini API key in Keychain."
        }
    }

    private var trimmedCustomSaveDirectory: String {
        customSaveDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedChapterSearchQuery: String {
        chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectedStorageDestination() throws -> AudioStorageCoordinator.Destination {
        switch saveLocationMode {
        case .managedInbox:
            return .managedInbox
        case .customFolder:
            guard !trimmedCustomSaveDirectory.isEmpty else {
                throw AudioStorageCoordinator.StorageError.customDirectoryNotConfigured
            }
            return .customDirectory(URL(fileURLWithPath: trimmedCustomSaveDirectory, isDirectory: true))
        }
    }

    private func initialCustomFolderURL() -> URL {
        let trimmedPath = trimmedCustomSaveDirectory
        if !trimmedPath.isEmpty {
            return URL(fileURLWithPath: trimmedPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static func resolveKokoroPythonPath(defaults: UserDefaults, bundle: Bundle) -> String {
        resolvePythonPath(
            defaults: defaults,
            defaultsKey: Keys.kokoroPythonPath,
            bundle: bundle,
            bundledRuntimeDirectory: "KokoroRuntime",
            localRelativePath: ".venv-kokoro/bin/python3"
        )
    }

    private static func resolveVoxtralPythonPath(defaults: UserDefaults, bundle: Bundle) -> String {
        resolvePythonPath(
            defaults: defaults,
            defaultsKey: Keys.voxtralPythonPath,
            bundle: bundle,
            bundledRuntimeDirectory: "VoxtralRuntime",
            localRelativePath: ".venv-voxtral/bin/python3"
        )
    }

    private static func resolvePythonPath(
        defaults: UserDefaults,
        defaultsKey: String,
        bundle: Bundle,
        bundledRuntimeDirectory: String,
        localRelativePath: String
    ) -> String {
        if let bundledPath = detectBundledPythonPath(bundle: bundle, runtimeDirectory: bundledRuntimeDirectory) {
            defaults.set(bundledPath, forKey: defaultsKey)
            return bundledPath
        }

        let savedPath = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPath = (savedPath?.isEmpty == false ? savedPath! : "/usr/bin/python3")

        if let savedPath, savedPath != "/usr/bin/python3", FileManager.default.isExecutableFile(atPath: savedPath) {
            return savedPath
        }

        if let detectedPath = detectLocalPythonPath(relativePath: localRelativePath) {
            defaults.set(detectedPath, forKey: defaultsKey)
            return detectedPath
        }

        return fallbackPath
    }

    private static func detectBundledPythonPath(bundle: Bundle, runtimeDirectory: String) -> String? {
        let fileManager = FileManager.default
        guard let resourcesURL = bundle.resourceURL else {
            return nil
        }

        let candidate = resourcesURL
            .appendingPathComponent(runtimeDirectory, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
            .path

        return fileManager.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private static func detectLocalPythonPath(relativePath: String) -> String? {
        let fileManager = FileManager.default
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let candidates = [
            "\(sourceRoot)/\(relativePath)",
            "\(NSHomeDirectory())/dev/audio_local/\(relativePath)"
        ]

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
