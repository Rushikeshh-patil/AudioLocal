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

    static let outputExtension = "m4b"

    func transcodeSpeechWAV(at sourceURL: URL, to destinationURL: URL) throws {
        let executable = "/usr/bin/afconvert"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw TranscodeError.toolMissing
        }

        let stderrPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            sourceURL.path,
            "-o", destinationURL.path,
            "-f", "m4bf",
            "-d", "aac",
            "-b", "48000",
            "-q", "127",
            "-s", "3"
        ]
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
}
