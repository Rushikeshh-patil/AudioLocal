import Foundation

struct VolumeManager: Sendable {
    static let shareURLString = "smb://100.73.8.90/privateserver"
    static let mountedVolumeName = "privateserver"
    static let relativeInboxPath = "ubuntu/my-audio-cloud/library/articles/Inbox"
    static let inboxRootPath = "/Volumes/\(mountedVolumeName)/\(relativeInboxPath)"

    enum VolumeError: LocalizedError {
        case mountCommandFailed
        case mountTimedOut

        var errorDescription: String? {
            switch self {
            case .mountCommandFailed:
                return "Could not ask macOS to mount the SMB share."
            case .mountTimedOut:
                return "The SMB share did not mount in time."
            }
        }
    }

    private let shareURL = URL(string: Self.shareURLString)!

    func ensureInboxDirectoryAvailable() async throws -> URL {
        if let mountedRoot = mountedShareRoot() {
            return try ensureInboxDirectory(in: mountedRoot)
        }

        try openShareInFinder()

        let timeout = Date().addingTimeInterval(45)
        while Date() < timeout {
            try await Task.sleep(for: .seconds(2))
            if let mountedRoot = mountedShareRoot() {
                return try ensureInboxDirectory(in: mountedRoot)
            }
        }

        throw VolumeError.mountTimedOut
    }

    private func mountedShareRoot() -> URL? {
        let fileManager = FileManager.default
        let volumeURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumeURLs.first { url in
            let resourceValues = try? url.resourceValues(forKeys: [.volumeNameKey])
            let name = resourceValues?.volumeName?.lowercased()
            return name == Self.mountedVolumeName.lowercased() || url.lastPathComponent.lowercased() == Self.mountedVolumeName.lowercased()
        }
    }

    private func ensureInboxDirectory(in root: URL) throws -> URL {
        let directory = Self.relativeInboxPath
            .split(separator: "/")
            .reduce(root) { partial, component in
                partial.appendingPathComponent(String(component), isDirectory: true)
            }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func openShareInFinder() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [shareURL.absoluteString]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw VolumeError.mountCommandFailed
        }

        guard process.terminationStatus == 0 else {
            throw VolumeError.mountCommandFailed
        }
    }
}
