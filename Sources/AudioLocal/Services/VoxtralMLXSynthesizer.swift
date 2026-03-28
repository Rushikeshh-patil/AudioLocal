import Foundation

struct VoxtralMLXSynthesizer {
    static let defaultModelID = "mlx-community/Voxtral-4B-TTS-2603-mlx-bf16"

    struct SynthesisResult {
        let audioData: Data
        let device: String?
    }

    enum SynthError: LocalizedError {
        case helperMissing
        case unsupportedPlatform
        case unreadableOutput
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "The bundled Voxtral MLX helper script is missing."
            case .unsupportedPlatform:
                return "Voxtral MLX requires Apple Silicon."
            case .unreadableOutput:
                return "Voxtral did not produce an output audio file."
            case let .processFailed(message):
                return "Voxtral MLX synthesis failed: \(message)"
            }
        }
    }

    func synthesize(
        text: String,
        pythonExecutable: String,
        model: String,
        voice: String
    ) async throws -> SynthesisResult {
        #if !arch(arm64)
        throw SynthError.unsupportedPlatform
        #else
        return try await Task.detached(priority: .userInitiated) { () throws -> SynthesisResult in
            guard let scriptURL = Bundle.module.url(forResource: "voxtral_mlx_fallback", withExtension: "py") else {
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
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonExecutable)
            process.arguments = [
                scriptURL.path,
                "--input", inputURL.path,
                "--output", outputURL.path,
                "--model", model,
                "--voice", voice
            ]
            process.environment = resolvedEnvironment(for: pythonExecutable)
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            do {
                try process.run()
            } catch {
                throw SynthError.processFailed(error.localizedDescription)
            }

            process.waitUntilExit()

            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""

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
        #endif
    }

    private func resolvedEnvironment(for pythonExecutable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        let cacheHome = cacheHome(for: pythonExecutable)
        let hubCache = "\(cacheHome)/hub"
        environment["HF_HOME"] = cacheHome
        environment["HF_HUB_CACHE"] = hubCache
        environment["HUGGINGFACE_HUB_CACHE"] = hubCache

        if pythonExecutable.contains("/VoxtralRuntime/bin/python3"),
           FileManager.default.fileExists(atPath: "\(hubCache)/models--mlx-community--Voxtral-4B-TTS-2603-mlx-bf16") {
            environment["HF_HUB_OFFLINE"] = "1"
        } else {
            environment.removeValue(forKey: "HF_HUB_OFFLINE")
        }

        return environment
    }

    private func cacheHome(for pythonExecutable: String) -> String {
        let fileManager = FileManager.default

        if let resourcesURL = Bundle.main.resourceURL {
            let bundledCache = resourcesURL
                .appendingPathComponent("VoxtralRuntime", isDirectory: true)
                .appendingPathComponent("cache", isDirectory: true)
                .appendingPathComponent("huggingface", isDirectory: true)
                .path
            if fileManager.fileExists(atPath: bundledCache), pythonExecutable.contains("/VoxtralRuntime/bin/python3") {
                return bundledCache
            }
        }

        if let appSupportCache = applicationSupportCacheHome() {
            return appSupportCache
        }

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let localCache = "\(sourceRoot)/.voxtral-cache/huggingface"
        if fileManager.fileExists(atPath: localCache) {
            return localCache
        }

        return "\(NSHomeDirectory())/.cache/huggingface"
    }

    private func applicationSupportCacheHome() -> String? {
        do {
            let baseURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return baseURL
                .appendingPathComponent("AudioLocal", isDirectory: true)
                .appendingPathComponent("VoxtralModels", isDirectory: true)
                .appendingPathComponent("huggingface", isDirectory: true)
                .path
        } catch {
            return nil
        }
    }

    private static func parseDevice(from output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.lowercased().hasPrefix("voxtral device:") }
            .map { line in
                line.replacingOccurrences(of: "Voxtral device:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }
}
