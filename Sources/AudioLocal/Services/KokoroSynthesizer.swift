import Foundation

private final class KokoroPipeCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AudioLocal.KokoroPipeCapture")
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        queue.sync {
            stdoutData.append(chunk)
        }
    }

    func appendStderr(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        queue.sync {
            stderrData.append(chunk)
        }
    }

    func snapshot(appendingStdout trailingStdout: Data, stderr trailingStderr: Data) -> (stdout: Data, stderr: Data) {
        queue.sync {
            if !trailingStdout.isEmpty {
                stdoutData.append(trailingStdout)
            }
            if !trailingStderr.isEmpty {
                stderrData.append(trailingStderr)
            }

            return (stdoutData, stderrData)
        }
    }
}

struct KokoroSynthesizer {
    struct SynthesisResult {
        let audioData: Data
        let device: String?
    }

    enum SynthError: LocalizedError {
        case helperMissing
        case unreadableOutput
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "The bundled Kokoro helper script is missing."
            case .unreadableOutput:
                return "Kokoro did not produce an output audio file."
            case let .processFailed(message):
                return "Kokoro synthesis failed: \(message)"
            }
        }
    }

    func synthesize(
        text: String,
        pythonExecutable: String,
        voice: String,
        speed: Double
    ) async throws -> SynthesisResult {
        try await Task.detached(priority: .userInitiated) { () throws -> SynthesisResult in
            guard let scriptURL = Bundle.module.url(forResource: "kokoro_fallback", withExtension: "py") else {
                throw SynthError.helperMissing
            }

            let fileManager = FileManager.default
            let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

            defer {
                try? fileManager.removeItem(at: tempDirectory)
            }

            let inputURL = tempDirectory.appendingPathComponent("article.txt")
            let outputURL = tempDirectory.appendingPathComponent("article.wav")

            try text.write(to: inputURL, atomically: true, encoding: .utf8)

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            let outputCapture = KokoroPipeCapture()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = [
                scriptURL.path,
                "--input", inputURL.path,
                "--output", outputURL.path,
                "--voice", voice,
                "--speed", String(format: "%.2f", speed)
            ]
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }

                outputCapture.appendStdout(chunk)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }

                outputCapture.appendStderr(chunk)
            }

            do {
                try process.run()
            } catch {
                throw SynthError.processFailed(error.localizedDescription)
            }

            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let trailingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let trailingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let capturedOutput = outputCapture.snapshot(appendingStdout: trailingStdout, stderr: trailingStderr)

            let stderrText = String(data: capturedOutput.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            let stdoutText = String(data: capturedOutput.stdout, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw SynthError.processFailed(stderrText)
            }

            guard let data = try? Data(contentsOf: outputURL), !data.isEmpty else {
                throw SynthError.unreadableOutput
            }

            return SynthesisResult(
                audioData: data,
                device: Self.parseDevice(from: stdoutText)
            )
        }.value
    }

    private static func parseDevice(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.lowercased().hasPrefix("kokoro device:") }
            .map { line in
                line.replacingOccurrences(of: "Kokoro device:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
}
