import Foundation

struct VoxtralVoiceCatalog {
    struct Voice: Identifiable, Hashable {
        let id: String
        let group: String
        let label: String

        var displayName: String {
            "\(label) (\(group))"
        }
    }

    static let allVoices: [Voice] = [
        .init(id: "casual_male", group: "English", label: "Casual Male"),
        .init(id: "casual_female", group: "English", label: "Casual Female"),
        .init(id: "cheerful_female", group: "English", label: "Cheerful Female"),
        .init(id: "neutral_male", group: "English", label: "Neutral Male"),
        .init(id: "neutral_female", group: "English", label: "Neutral Female"),
        .init(id: "fr_male", group: "French", label: "Male"),
        .init(id: "fr_female", group: "French", label: "Female"),
        .init(id: "es_male", group: "Spanish", label: "Male"),
        .init(id: "es_female", group: "Spanish", label: "Female"),
        .init(id: "de_male", group: "German", label: "Male"),
        .init(id: "de_female", group: "German", label: "Female"),
        .init(id: "it_male", group: "Italian", label: "Male"),
        .init(id: "it_female", group: "Italian", label: "Female"),
        .init(id: "pt_male", group: "Portuguese", label: "Male"),
        .init(id: "pt_female", group: "Portuguese", label: "Female"),
        .init(id: "nl_male", group: "Dutch", label: "Male"),
        .init(id: "nl_female", group: "Dutch", label: "Female"),
        .init(id: "ar_male", group: "Arabic", label: "Male"),
        .init(id: "hi_male", group: "Hindi", label: "Male"),
        .init(id: "hi_female", group: "Hindi", label: "Female")
    ]

    static let groupedVoices: [(group: String, voices: [Voice])] = Dictionary(grouping: allVoices, by: \.group)
        .map { (group: $0.key, voices: $0.value.sorted { $0.id < $1.id }) }
        .sorted { $0.group < $1.group }
}
