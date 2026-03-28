namespace AudioLocal.Windows.Core.Models;

public sealed record VoiceOption(string Id, string Group, string DisplayName);

public static class KokoroVoiceCatalog
{
    public static IReadOnlyList<VoiceOption> All { get; } =
    [
        Voice("af_alloy", "American English"),
        Voice("af_aoede", "American English"),
        Voice("af_bella", "American English"),
        Voice("af_heart", "American English"),
        Voice("af_jessica", "American English"),
        Voice("af_kore", "American English"),
        Voice("af_nicole", "American English"),
        Voice("af_nova", "American English"),
        Voice("af_river", "American English"),
        Voice("af_sarah", "American English"),
        Voice("af_sky", "American English"),
        Voice("am_adam", "American English"),
        Voice("am_echo", "American English"),
        Voice("am_eric", "American English"),
        Voice("am_fenrir", "American English"),
        Voice("am_liam", "American English"),
        Voice("am_michael", "American English"),
        Voice("am_onyx", "American English"),
        Voice("am_puck", "American English"),
        Voice("am_santa", "American English"),
        Voice("bf_alice", "British English"),
        Voice("bf_emma", "British English"),
        Voice("bf_isabella", "British English"),
        Voice("bf_lily", "British English"),
        Voice("bm_daniel", "British English"),
        Voice("bm_fable", "British English"),
        Voice("bm_george", "British English"),
        Voice("bm_lewis", "British English"),
        Voice("ef_dora", "Spanish"),
        Voice("em_alex", "Spanish"),
        Voice("em_santa", "Spanish"),
        Voice("ff_siwis", "French"),
        Voice("hf_alpha", "Hindi"),
        Voice("hf_beta", "Hindi"),
        Voice("hm_omega", "Hindi"),
        Voice("hm_psi", "Hindi"),
        Voice("if_sara", "Italian"),
        Voice("im_nicola", "Italian"),
        Voice("jf_alpha", "Japanese"),
        Voice("jf_gongitsune", "Japanese"),
        Voice("jf_nezumi", "Japanese"),
        Voice("jf_tebukuro", "Japanese"),
        Voice("jm_kumo", "Japanese"),
        Voice("pf_dora", "Portuguese"),
        Voice("pm_alex", "Portuguese"),
        Voice("pm_santa", "Portuguese"),
        Voice("zf_xiaobei", "Mandarin Chinese"),
        Voice("zf_xiaoni", "Mandarin Chinese"),
        Voice("zf_xiaoxiao", "Mandarin Chinese"),
        Voice("zf_xiaoyi", "Mandarin Chinese"),
        Voice("zm_yunjian", "Mandarin Chinese"),
        Voice("zm_yunxi", "Mandarin Chinese"),
        Voice("zm_yunxia", "Mandarin Chinese"),
        Voice("zm_yunyang", "Mandarin Chinese")
    ];

    public static string DisplayName(string id) =>
        All.FirstOrDefault(voice => string.Equals(voice.Id, id, StringComparison.Ordinal))?.DisplayName ?? id;

    private static VoiceOption Voice(string id, string group)
    {
        var parts = id.Split('_', 2, StringSplitOptions.RemoveEmptyEntries);
        var prefix = parts.Length > 0 ? parts[0].ToUpperInvariant() : id;
        var name = parts.Length > 1
            ? string.Join(' ', parts[1].Split('_', StringSplitOptions.RemoveEmptyEntries).Select(static value => Capitalize(value)))
            : id;
        return new VoiceOption(id, group, $"{name} ({prefix})");
    }

    private static string Capitalize(string value) =>
        string.IsNullOrWhiteSpace(value) ? value : char.ToUpperInvariant(value[0]) + value[1..];
}

public static class GeminiVoiceCatalog
{
    public static IReadOnlyList<VoiceOption> All { get; } =
    [
        new("Zephyr", "Bright", "Zephyr - Bright"),
        new("Puck", "Upbeat", "Puck - Upbeat"),
        new("Charon", "Informative", "Charon - Informative"),
        new("Kore", "Firm", "Kore - Firm"),
        new("Fenrir", "Excitable", "Fenrir - Excitable"),
        new("Leda", "Youthful", "Leda - Youthful"),
        new("Orus", "Firm", "Orus - Firm"),
        new("Aoede", "Breezy", "Aoede - Breezy"),
        new("Callirrhoe", "Easy-going", "Callirrhoe - Easy-going"),
        new("Autonoe", "Bright", "Autonoe - Bright"),
        new("Enceladus", "Breathy", "Enceladus - Breathy"),
        new("Iapetus", "Clear", "Iapetus - Clear"),
        new("Umbriel", "Easy-going", "Umbriel - Easy-going"),
        new("Algieba", "Smooth", "Algieba - Smooth"),
        new("Despina", "Smooth", "Despina - Smooth"),
        new("Erinome", "Clear", "Erinome - Clear"),
        new("Algenib", "Gravelly", "Algenib - Gravelly"),
        new("Rasalgethi", "Informative", "Rasalgethi - Informative"),
        new("Laomedeia", "Upbeat", "Laomedeia - Upbeat"),
        new("Achernar", "Soft", "Achernar - Soft"),
        new("Alnilam", "Firm", "Alnilam - Firm"),
        new("Schedar", "Even", "Schedar - Even"),
        new("Gacrux", "Mature", "Gacrux - Mature"),
        new("Pulcherrima", "Forward", "Pulcherrima - Forward"),
        new("Achird", "Friendly", "Achird - Friendly"),
        new("Zubenelgenubi", "Casual", "Zubenelgenubi - Casual"),
        new("Vindemiatrix", "Gentle", "Vindemiatrix - Gentle"),
        new("Sadachbia", "Lively", "Sadachbia - Lively"),
        new("Sadaltager", "Knowledgeable", "Sadaltager - Knowledgeable"),
        new("Sulafat", "Warm", "Sulafat - Warm")
    ];
}
