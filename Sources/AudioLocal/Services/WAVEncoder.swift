import Foundation

enum WAVEncoder {
    enum WAVError: LocalizedError {
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedFormat(format):
                return "Unsupported audio format returned by Gemini: \(format)"
            }
        }
    }

    static func wrapIfNeeded(audioData: Data, mimeType: String) throws -> Data {
        if audioData.starts(with: Data([0x52, 0x49, 0x46, 0x46])) {
            return audioData
        }

        let normalized = mimeType.lowercased()
        guard normalized.contains("audio") else {
            throw WAVError.unsupportedFormat(mimeType)
        }

        let sampleRate = parseIntegerParameter(named: "rate", from: normalized) ?? 24_000
        let channels = parseIntegerParameter(named: "channels", from: normalized) ?? 1

        return makeWAV(pcmData: audioData, sampleRate: sampleRate, channels: channels, bitsPerSample: 16)
    }

    private static func parseIntegerParameter(named name: String, from mimeType: String) -> Int? {
        for part in mimeType.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(name)=") {
                return Int(trimmed.dropFirst(name.count + 1))
            }
        }
        return nil
    }

    private static func makeWAV(
        pcmData: Data,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let chunkSize = 36 + pcmData.count

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLE(UInt32(chunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLE(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}
