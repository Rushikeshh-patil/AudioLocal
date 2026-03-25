import Foundation

struct GeminiTTSClient {
    struct SynthesisResult {
        let audioData: Data
        let mimeType: String
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    enum ClientError: LocalizedError {
        case missingAPIKey
        case requestEncodingFailed
        case invalidResponse
        case api(statusCode: Int, message: String)
        case emptyAudio
        case invalidBase64
        case timedOut
        case transport(message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Gemini API key is missing."
            case .requestEncodingFailed:
                return "Failed to encode the Gemini request."
            case .invalidResponse:
                return "Gemini returned an unreadable response."
            case let .api(statusCode, message):
                return "Gemini request failed (\(statusCode)): \(message)"
            case .emptyAudio:
                return "Gemini returned no audio payload."
            case .invalidBase64:
                return "Gemini returned invalid audio data."
            case .timedOut:
                return "Gemini timed out while generating audio. Try shorter text or use Automatic mode to fall back to Kokoro."
            case let .transport(message):
                return "Gemini request failed before completion: \(message)"
            }
        }

        var shouldFallbackToLocal: Bool {
            switch self {
            case .missingAPIKey:
                return true
            case .timedOut:
                return true
            case let .api(statusCode, message):
                let normalized = message.lowercased()
                return statusCode == 429 ||
                    (500...599).contains(statusCode) ||
                    normalized.contains("quota") ||
                    normalized.contains("resource exhausted") ||
                    normalized.contains("rate limit") ||
                    normalized.contains("limit exceeded")
            default:
                return false
            }
        }
    }

    func synthesize(
        text: String,
        apiKey: String,
        model: String,
        voiceName: String
    ) async throws -> SynthesisResult {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw ClientError.missingAPIKey
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/v1beta/models/\(model):generateContent"
        components.queryItems = [
            URLQueryItem(name: "key", value: trimmedAPIKey)
        ]

        guard let url = components.url else {
            throw ClientError.invalidResponse
        }

        let payload = RequestPayload(
            contents: [
                .init(parts: [.init(text: text)])
            ],
            generationConfig: .init(
                responseModalities: ["AUDIO"],
                speechConfig: .init(
                    voiceConfig: .init(
                        prebuiltVoiceConfig: .init(voiceName: voiceName)
                    )
                )
            )
        )

        guard let body = try? JSONEncoder().encode(payload) else {
            throw ClientError.requestEncodingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ClientError.timedOut
        } catch let error as URLError {
            throw ClientError.transport(message: error.localizedDescription)
        } catch {
            throw ClientError.transport(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw ClientError.api(
                statusCode: httpResponse.statusCode,
                message: errorEnvelope?.error.message ?? "Unknown Gemini error"
            )
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        guard
            let inlineData = envelope.candidates?.first?.content.parts.first(where: { $0.inlineData != nil })?.inlineData
        else {
            throw ClientError.emptyAudio
        }

        guard let decodedData = Data(base64Encoded: inlineData.data, options: .ignoreUnknownCharacters) else {
            throw ClientError.invalidBase64
        }

        return SynthesisResult(audioData: decodedData, mimeType: inlineData.mimeType)
    }
}

private extension GeminiTTSClient {
    struct RequestPayload: Encodable {
        let contents: [Content]
        let generationConfig: GenerationConfig
    }

    struct Content: Encodable {
        let parts: [TextPart]
    }

    struct TextPart: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let responseModalities: [String]
        let speechConfig: SpeechConfig
    }

    struct SpeechConfig: Encodable {
        let voiceConfig: VoiceConfig
    }

    struct VoiceConfig: Encodable {
        let prebuiltVoiceConfig: PrebuiltVoiceConfig
    }

    struct PrebuiltVoiceConfig: Encodable {
        let voiceName: String
    }

    struct ResponseEnvelope: Decodable {
        let candidates: [Candidate]?
    }

    struct Candidate: Decodable {
        let content: CandidateContent
    }

    struct CandidateContent: Decodable {
        let parts: [ResponsePart]
    }

    struct ResponsePart: Decodable {
        let inlineData: InlineData?
    }

    struct InlineData: Decodable {
        let mimeType: String
        let data: String
    }

    struct ErrorEnvelope: Decodable {
        let error: APIError
    }

    struct APIError: Decodable {
        let message: String
    }
}
