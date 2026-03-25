import Foundation

enum AudioExportFormat: String, CaseIterable, Identifiable {
    case m4b
    case m4a
    case wav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m4b:
            return "M4B audiobook"
        case .m4a:
            return "M4A audio"
        case .wav:
            return "WAV"
        }
    }

    var filenameExtension: String {
        rawValue
    }

    var detail: String {
        switch self {
        case .m4b:
            return "AAC audiobook file. Best fit for Audiobookshelf and Apple audiobook apps."
        case .m4a:
            return "AAC audio file. Smaller than WAV and broadly supported across players."
        case .wav:
            return "Uncompressed WAV. Largest files, but no extra conversion step."
        }
    }

    var processingDescription: String {
        switch self {
        case .m4b:
            return "compressed to AAC `.m4b`"
        case .m4a:
            return "compressed to AAC `.m4a`"
        case .wav:
            return "kept as uncompressed `.wav`"
        }
    }
}
