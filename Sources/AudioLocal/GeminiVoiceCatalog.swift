import Foundation

struct GeminiVoiceCatalog {
    struct Voice: Identifiable, Hashable {
        let id: String
        let style: String

        var displayName: String {
            "\(id) - \(style)"
        }
    }

    static let allVoices: [Voice] = [
        .init(id: "Zephyr", style: "Bright"),
        .init(id: "Puck", style: "Upbeat"),
        .init(id: "Charon", style: "Informative"),
        .init(id: "Kore", style: "Firm"),
        .init(id: "Fenrir", style: "Excitable"),
        .init(id: "Leda", style: "Youthful"),
        .init(id: "Orus", style: "Firm"),
        .init(id: "Aoede", style: "Breezy"),
        .init(id: "Callirrhoe", style: "Easy-going"),
        .init(id: "Autonoe", style: "Bright"),
        .init(id: "Enceladus", style: "Breathy"),
        .init(id: "Iapetus", style: "Clear"),
        .init(id: "Umbriel", style: "Easy-going"),
        .init(id: "Algieba", style: "Smooth"),
        .init(id: "Despina", style: "Smooth"),
        .init(id: "Erinome", style: "Clear"),
        .init(id: "Algenib", style: "Gravelly"),
        .init(id: "Rasalgethi", style: "Informative"),
        .init(id: "Laomedeia", style: "Upbeat"),
        .init(id: "Achernar", style: "Soft"),
        .init(id: "Alnilam", style: "Firm"),
        .init(id: "Schedar", style: "Even"),
        .init(id: "Gacrux", style: "Mature"),
        .init(id: "Pulcherrima", style: "Forward"),
        .init(id: "Achird", style: "Friendly"),
        .init(id: "Zubenelgenubi", style: "Casual"),
        .init(id: "Vindemiatrix", style: "Gentle"),
        .init(id: "Sadachbia", style: "Lively"),
        .init(id: "Sadaltager", style: "Knowledgeable"),
        .init(id: "Sulafat", style: "Warm")
    ]
}
