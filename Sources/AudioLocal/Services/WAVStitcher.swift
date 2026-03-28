import Foundation

struct WAVStitcher: Sendable {
    enum StitchError: LocalizedError {
        case noAudio
        case unsupportedFormat
        case mismatchedFormats

        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "No chapter audio was generated."
            case .unsupportedFormat:
                return "The generated chapter audio could not be stitched because it is not PCM WAV."
            case .mismatchedFormats:
                return "The generated chapter audio could not be stitched because the WAV formats do not match."
            }
        }
    }

    func stitch(chapterAudio: [Data], pauseBetweenChapters: TimeInterval = 0.85) throws -> Data {
        guard !chapterAudio.isEmpty else {
            throw StitchError.noAudio
        }

        let parsedSegments = try chapterAudio.map(parseWAV)
        guard let firstSegment = parsedSegments.first else {
            throw StitchError.noAudio
        }

        for segment in parsedSegments.dropFirst() where segment.format != firstSegment.format {
            throw StitchError.mismatchedFormats
        }

        if parsedSegments.count == 1 {
            return chapterAudio[0]
        }

        let silenceFrameCount = Int((Double(firstSegment.format.sampleRate) * pauseBetweenChapters).rounded())
        let silenceByteCount = silenceFrameCount * Int(firstSegment.format.blockAlign)
        let silence = Data(repeating: 0, count: max(silenceByteCount, 0))

        var combinedPCM = Data()
        for (index, segment) in parsedSegments.enumerated() {
            combinedPCM.append(segment.pcmData)
            if index < parsedSegments.count - 1 {
                combinedPCM.append(silence)
            }
        }

        return WAVEncoder.makeWAV(
            pcmData: combinedPCM,
            sampleRate: Int(firstSegment.format.sampleRate),
            channels: Int(firstSegment.format.channels),
            bitsPerSample: Int(firstSegment.format.bitsPerSample)
        )
    }

    private func parseWAV(_ data: Data) throws -> ParsedWAV {
        guard data.count >= 44 else {
            throw StitchError.unsupportedFormat
        }

        guard data.asciiString(at: 0, count: 4) == "RIFF",
              data.asciiString(at: 8, count: 4) == "WAVE" else {
            throw StitchError.unsupportedFormat
        }

        var offset = 12
        var format: WAVFormat?
        var pcmData: Data?

        while offset + 8 <= data.count {
            let chunkID = data.asciiString(at: offset, count: 4)
            let chunkSize = Int(data.readUInt32LE(at: offset + 4))
            let chunkStart = offset + 8
            let nextChunkOffset = chunkStart + chunkSize + (chunkSize % 2)

            guard nextChunkOffset <= data.count else {
                throw StitchError.unsupportedFormat
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw StitchError.unsupportedFormat
                }

                let audioFormat = data.readUInt16LE(at: chunkStart)
                let channels = data.readUInt16LE(at: chunkStart + 2)
                let sampleRate = data.readUInt32LE(at: chunkStart + 4)
                let blockAlign = data.readUInt16LE(at: chunkStart + 12)
                let bitsPerSample = data.readUInt16LE(at: chunkStart + 14)

                guard audioFormat == 1, bitsPerSample == 16 else {
                    throw StitchError.unsupportedFormat
                }

                format = WAVFormat(
                    sampleRate: sampleRate,
                    channels: channels,
                    bitsPerSample: bitsPerSample,
                    blockAlign: blockAlign
                )
            } else if chunkID == "data" {
                pcmData = data.subdata(in: chunkStart..<chunkStart + chunkSize)
            }

            offset = nextChunkOffset
        }

        guard let format, let pcmData else {
            throw StitchError.unsupportedFormat
        }

        return ParsedWAV(format: format, pcmData: pcmData)
    }
}

private struct ParsedWAV {
    let format: WAVFormat
    let pcmData: Data
}

private struct WAVFormat: Equatable {
    let sampleRate: UInt32
    let channels: UInt16
    let bitsPerSample: UInt16
    let blockAlign: UInt16
}

private extension Data {
    func asciiString(at offset: Int, count: Int) -> String {
        String(decoding: self[offset..<offset + count], as: UTF8.self)
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        let lower = UInt16(self[offset])
        let upper = UInt16(self[offset + 1]) << 8
        return lower | upper
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
