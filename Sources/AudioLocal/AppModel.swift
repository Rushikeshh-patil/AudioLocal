import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum ProviderMode: String, CaseIterable, Identifiable {
        case kokoroOnly
        case automatic
        case geminiOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kokoroOnly:
                return "Kokoro only"
            case .automatic:
                return "Automatic"
            case .geminiOnly:
                return "Gemini only"
            }
        }

        var detail: String {
            switch self {
            case .kokoroOnly:
                return "Use the bundled local Kokoro runtime only. No Gemini API key is required."
            case .automatic:
                return "Use Kokoro first. If Kokoro fails and a Gemini API key is configured, fall back to Gemini."
            case .geminiOnly:
                return "Use Gemini and fail on any Gemini error."
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

    @Published var articleTitle: String {
        didSet { defaults.set(articleTitle, forKey: Keys.articleTitle) }
    }

    @Published var articleBody: String {
        didSet { defaults.set(articleBody, forKey: Keys.articleBody) }
    }

    @Published var providerMode: ProviderMode {
        didSet { defaults.set(providerMode.rawValue, forKey: Keys.providerMode) }
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
    @Published var lastKokoroDevice = ""
    @Published var isGenerating = false

    private let defaults = UserDefaults.standard
    private let keychain = KeychainStore(service: "com.rushikeshpatil.AudioLocal")
    private let geminiClient = GeminiTTSClient()
    private let kokoroSynthesizer = KokoroSynthesizer()
    private let storageCoordinator = AudioStorageCoordinator()

    private enum Keys {
        static let articleTitle = "draft.articleTitle"
        static let articleBody = "draft.articleBody"
        static let providerMode = "settings.providerMode"
        static let geminiModel = "settings.geminiModel"
        static let geminiVoice = "settings.geminiVoice"
        static let kokoroPythonPath = "settings.kokoroPythonPath"
        static let kokoroVoice = "settings.kokoroVoice"
        static let kokoroSpeed = "settings.kokoroSpeed"
        static let saveLocationMode = "settings.saveLocationMode"
        static let exportFormat = "settings.exportFormat"
        static let customSaveDirectory = "settings.customSaveDirectory"
    }

    init() {
        articleTitle = defaults.string(forKey: Keys.articleTitle) ?? ""
        articleBody = defaults.string(forKey: Keys.articleBody) ?? ""
        providerMode = ProviderMode(rawValue: defaults.string(forKey: Keys.providerMode) ?? "") ?? .kokoroOnly
        geminiAPIKey = (try? keychain.read(account: "gemini_api_key")) ?? ""
        geminiModel = defaults.string(forKey: Keys.geminiModel) ?? "gemini-2.5-flash-preview-tts"
        geminiVoice = defaults.string(forKey: Keys.geminiVoice) ?? "Kore"
        kokoroPythonPath = Self.resolveKokoroPythonPath(defaults: defaults, bundle: .main)
        kokoroVoice = defaults.string(forKey: Keys.kokoroVoice) ?? "af_heart"
        let storedSpeed = defaults.object(forKey: Keys.kokoroSpeed) as? Double
        kokoroSpeed = storedSpeed ?? 1.0
        saveLocationMode = SaveLocationMode(rawValue: defaults.string(forKey: Keys.saveLocationMode) ?? "") ?? .managedInbox
        exportFormat = AudioExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? "") ?? .m4b
        customSaveDirectory = defaults.string(forKey: Keys.customSaveDirectory) ?? ""
    }

    var canGenerate: Bool {
        !articleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !articleBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isSaveLocationConfigured
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
            statusMessage = isSaveLocationConfigured ? "Enter both a title and article text." : "Choose a save location before generating audio."
            return
        }

        isGenerating = true
        lastSavedPath = ""
        lastBackend = ""
        lastKokoroDevice = ""

        defer { isGenerating = false }

        do {
            let itemName = makeItemName()
            let destination = try selectedStorageDestination()
            let result: GeneratedAudio

            switch providerMode {
            case .automatic:
                result = try await synthesizeAutomatically()
            case .geminiOnly:
                result = try await synthesizeWithGemini()
            case .kokoroOnly:
                result = try await synthesizeWithKokoro()
            }

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
        } catch {
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

    private struct GeneratedAudio {
        let wavData: Data
        let backend: String
    }

    private func synthesizeAutomatically() async throws -> GeneratedAudio {
        do {
            return try await synthesizeWithKokoro()
        } catch {
            guard !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw error
            }

            statusMessage = "Kokoro unavailable for this request. Falling back to Gemini..."
            return try await synthesizeWithGemini()
        }
    }

    private func synthesizeWithGemini() async throws -> GeneratedAudio {
        statusMessage = "Generating audio with Gemini..."
        let result = try await geminiClient.synthesize(
            text: articleBody,
            apiKey: geminiAPIKey,
            model: geminiModel,
            voiceName: geminiVoice
        )
        let wavData = try WAVEncoder.wrapIfNeeded(audioData: result.audioData, mimeType: result.mimeType)
        return GeneratedAudio(wavData: wavData, backend: "Gemini")
    }

    private func synthesizeWithKokoro() async throws -> GeneratedAudio {
        statusMessage = "Generating audio with Kokoro..."
        let result = try await kokoroSynthesizer.synthesize(
            text: articleBody,
            pythonExecutable: kokoroPythonPath,
            voice: kokoroVoice,
            speed: kokoroSpeed
        )
        let device = result.device?.uppercased() ?? "CPU"
        lastKokoroDevice = device
        return GeneratedAudio(wavData: result.audioData, backend: "Kokoro (\(device))")
    }

    private func makeItemName() -> String {
        let title = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: .now)
        return "\(safeTitle.isEmpty ? "article" : safeTitle)-\(timestamp)"
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
        if let bundledPath = detectBundledKokoroPythonPath(bundle: bundle) {
            defaults.set(bundledPath, forKey: Keys.kokoroPythonPath)
            return bundledPath
        }

        let savedPath = defaults.string(forKey: Keys.kokoroPythonPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPath = (savedPath?.isEmpty == false ? savedPath! : "/usr/bin/python3")

        if let savedPath, savedPath != "/usr/bin/python3", FileManager.default.isExecutableFile(atPath: savedPath) {
            return savedPath
        }

        if let detectedPath = detectLocalKokoroPythonPath() {
            defaults.set(detectedPath, forKey: Keys.kokoroPythonPath)
            return detectedPath
        }

        return fallbackPath
    }

    private static func detectBundledKokoroPythonPath(bundle: Bundle) -> String? {
        let fileManager = FileManager.default
        guard let resourcesURL = bundle.resourceURL else {
            return nil
        }

        let candidate = resourcesURL
            .appendingPathComponent("KokoroRuntime", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
            .path

        return fileManager.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private static func detectLocalKokoroPythonPath() -> String? {
        let fileManager = FileManager.default
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let candidates = [
            "\(sourceRoot)/.venv-kokoro/bin/python3",
            "\(NSHomeDirectory())/dev/audio_local/.venv-kokoro/bin/python3"
        ]

        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }
}
