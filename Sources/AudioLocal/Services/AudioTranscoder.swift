import Foundation

struct AudioTranscoder: Sendable {
    enum TranscodeError: LocalizedError {
        case toolMissing
        case failed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .toolMissing:
                return "macOS audio conversion tool `afconvert` is missing."
            case let .failed(message):
                return "Audio conversion failed: \(message)"
            case .outputMissing:
                return "Audio conversion finished without producing an output file."
            }
        }
    }

    func exportSpeechAudio(at sourceURL: URL, to destinationURL: URL, format: AudioExportFormat) throws {
        if format == .wav {
            if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
                return
            }
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        let executable = "/usr/bin/afconvert"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw TranscodeError.toolMissing
        }

        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(for: format, sourceURL: sourceURL, destinationURL: destinationURL)
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw TranscodeError.failed(error.localizedDescription)
        }

        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown conversion error"

        guard process.terminationStatus == 0 else {
            throw TranscodeError.failed(stderrText)
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw TranscodeError.outputMissing
        }
    }

    private func arguments(for format: AudioExportFormat, sourceURL: URL, destinationURL: URL) -> [String] {
        switch format {
        case .m4b:
            return [
                sourceURL.path,
                destinationURL.path,
                "-f", "m4bf",
                "-d", "aac",
                "-b", "48000",
                "-q", "127",
                "-s", "3",
                "--media-kind", "Audiobook"
            ]
        case .m4a:
            return [
                sourceURL.path,
                destinationURL.path,
                "-f", "m4af",
                "-d", "aac",
                "-b", "48000",
                "-q", "127",
                "-s", "3"
            ]
        case .wav:
            return [sourceURL.path, destinationURL.path]
        }
    }
}
