import Foundation

struct KokoroVoiceCatalog {
    struct Voice: Identifiable, Hashable {
        let id: String
        let group: String

        var displayName: String {
            let parts = id.split(separator: "_", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return id }
            let prefix = parts[0].uppercased()
            let name = parts[1]
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
            return "\(name) (\(prefix))"
        }
    }

    static let allVoices: [Voice] = [
        .init(id: "af_alloy", group: "American English"),
        .init(id: "af_aoede", group: "American English"),
        .init(id: "af_bella", group: "American English"),
        .init(id: "af_heart", group: "American English"),
        .init(id: "af_jessica", group: "American English"),
        .init(id: "af_kore", group: "American English"),
        .init(id: "af_nicole", group: "American English"),
        .init(id: "af_nova", group: "American English"),
        .init(id: "af_river", group: "American English"),
        .init(id: "af_sarah", group: "American English"),
        .init(id: "af_sky", group: "American English"),
        .init(id: "am_adam", group: "American English"),
        .init(id: "am_echo", group: "American English"),
        .init(id: "am_eric", group: "American English"),
        .init(id: "am_fenrir", group: "American English"),
        .init(id: "am_liam", group: "American English"),
        .init(id: "am_michael", group: "American English"),
        .init(id: "am_onyx", group: "American English"),
        .init(id: "am_puck", group: "American English"),
        .init(id: "am_santa", group: "American English"),
        .init(id: "bf_alice", group: "British English"),
        .init(id: "bf_emma", group: "British English"),
        .init(id: "bf_isabella", group: "British English"),
        .init(id: "bf_lily", group: "British English"),
        .init(id: "bm_daniel", group: "British English"),
        .init(id: "bm_fable", group: "British English"),
        .init(id: "bm_george", group: "British English"),
        .init(id: "bm_lewis", group: "British English"),
        .init(id: "ef_dora", group: "Spanish"),
        .init(id: "em_alex", group: "Spanish"),
        .init(id: "em_santa", group: "Spanish"),
        .init(id: "ff_siwis", group: "French"),
        .init(id: "hf_alpha", group: "Hindi"),
        .init(id: "hf_beta", group: "Hindi"),
        .init(id: "hm_omega", group: "Hindi"),
        .init(id: "hm_psi", group: "Hindi"),
        .init(id: "if_sara", group: "Italian"),
        .init(id: "im_nicola", group: "Italian"),
        .init(id: "jf_alpha", group: "Japanese"),
        .init(id: "jf_gongitsune", group: "Japanese"),
        .init(id: "jf_nezumi", group: "Japanese"),
        .init(id: "jf_tebukuro", group: "Japanese"),
        .init(id: "jm_kumo", group: "Japanese"),
        .init(id: "pf_dora", group: "Portuguese"),
        .init(id: "pm_alex", group: "Portuguese"),
        .init(id: "pm_santa", group: "Portuguese"),
        .init(id: "zf_xiaobei", group: "Mandarin Chinese"),
        .init(id: "zf_xiaoni", group: "Mandarin Chinese"),
        .init(id: "zf_xiaoxiao", group: "Mandarin Chinese"),
        .init(id: "zf_xiaoyi", group: "Mandarin Chinese"),
        .init(id: "zm_yunjian", group: "Mandarin Chinese"),
        .init(id: "zm_yunxi", group: "Mandarin Chinese"),
        .init(id: "zm_yunxia", group: "Mandarin Chinese"),
        .init(id: "zm_yunyang", group: "Mandarin Chinese")
    ]

    static let groupedVoices: [(group: String, voices: [Voice])] = Dictionary(grouping: allVoices, by: \.group)
        .map { (group: $0.key, voices: $0.value.sorted { $0.id < $1.id }) }
        .sorted { $0.group < $1.group }

    static func displayName(for voiceID: String) -> String {
        allVoices.first(where: { $0.id == voiceID })?.displayName ?? voiceID
    }
}
