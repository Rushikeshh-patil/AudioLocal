import Foundation

struct AudioStorageCoordinator: Sendable {
    enum Destination: Sendable {
        case managedInbox
        case customDirectory(URL)
    }

    enum StorageError: LocalizedError {
        case customDirectoryNotConfigured
        case externalVolumeUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .customDirectoryNotConfigured:
                return "Choose a custom save folder before generating audio."
            case let .externalVolumeUnavailable(volumeName):
                return "The selected save location is on the volume `\(volumeName)`, which is not mounted right now."
            }
        }
    }

    private let volumeManager: VolumeManager
    private let transcoder: AudioTranscoder

    init(
        volumeManager: VolumeManager = VolumeManager(),
        transcoder: AudioTranscoder = AudioTranscoder()
    ) {
        self.volumeManager = volumeManager
        self.transcoder = transcoder
    }

    func saveAudio(
        _ wavData: Data,
        itemName: String,
        destination: Destination = .managedInbox,
        format: AudioExportFormat = .m4b
    ) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let stagingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
                "AudioLocal-\(UUID().uuidString)",
                isDirectory: true
            )

            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            defer {
                try? fileManager.removeItem(at: stagingDirectory)
            }

            let baseDirectory = try await resolveBaseDirectory(for: destination)
            let stagedFileURL = stagingDirectory.appendingPathComponent(itemName).appendingPathExtension("wav")
            let exportedFileURL = stagingDirectory
                .appendingPathComponent(itemName)
                .appendingPathExtension(format.filenameExtension)
            try wavData.write(to: stagedFileURL, options: .atomic)
            try transcoder.exportSpeechAudio(at: stagedFileURL, to: exportedFileURL, format: format)

            let itemDirectory = baseDirectory.appendingPathComponent(itemName, isDirectory: true)
            try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)

            let destinationURL = itemDirectory
                .appendingPathComponent(itemName)
                .appendingPathExtension(format.filenameExtension)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: exportedFileURL, to: destinationURL)
            return destinationURL
        }.value
    }

    private func resolveBaseDirectory(for destination: Destination) async throws -> URL {
        switch destination {
        case .managedInbox:
            return try await volumeManager.ensureInboxDirectoryAvailable()
        case let .customDirectory(directory):
            return try ensureCustomDirectoryAvailable(at: directory)
        }
    }

    private func ensureCustomDirectoryAvailable(at directory: URL) throws -> URL {
        let resolvedDirectory = directory.standardizedFileURL
        try ensureMountedVolumeExistsIfNeeded(for: resolvedDirectory)
        try FileManager.default.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
        return resolvedDirectory
    }

    private func ensureMountedVolumeExistsIfNeeded(for directory: URL) throws {
        let components = directory.pathComponents
        guard components.count > 2, components[1] == "Volumes" else {
            return
        }

        let volumeRoot = URL(fileURLWithPath: "/Volumes", isDirectory: true)
            .appendingPathComponent(components[2], isDirectory: true)
        let mountedVolumeURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []

        guard mountedVolumeURLs.contains(where: { $0.standardizedFileURL.path == volumeRoot.path }) else {
            throw StorageError.externalVolumeUnavailable(volumeRoot.lastPathComponent)
        }
    }
}
