using System.Net;
using System.Net.Http.Json;

namespace AudioLocal.Windows.Core.Services;

public sealed class GeminiTtsClient
{
    private readonly HttpClient httpClient;

    public GeminiTtsClient(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(15)
        };
    }

    public async Task<(byte[] AudioData, string MimeType)> SynthesizeAsync(
        string text,
        string apiKey,
        string model,
        string voiceName,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("Gemini API key is missing.");
        }

        var uri = new Uri($"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={Uri.EscapeDataString(apiKey.Trim())}");
        var request = new GeminiRequest(
            [new GeminiContent([new GeminiTextPart(text)])],
            new GeminiGenerationConfig(["AUDIO"], new GeminiSpeechConfig(new GeminiVoiceConfig(new GeminiPrebuiltVoiceConfig(voiceName)))));

        using var response = await httpClient.PostAsJsonAsync(uri, request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var errorText = await response.Content.ReadAsStringAsync(cancellationToken);
            throw new HttpRequestException(
                $"Gemini request failed ({(int)response.StatusCode}): {errorText}",
                inner: null,
                response.StatusCode);
        }

        var payload = await response.Content.ReadFromJsonAsync<GeminiResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException("Gemini returned an unreadable response.");
        var inlineData = payload.Candidates?
            .FirstOrDefault()?
            .Content?
            .Parts?
            .FirstOrDefault(static part => part.InlineData is not null)?
            .InlineData
            ?? throw new InvalidOperationException("Gemini returned no audio payload.");

        try
        {
            return (Convert.FromBase64String(inlineData.Data), inlineData.MimeType);
        }
        catch (FormatException exception)
        {
            throw new InvalidOperationException("Gemini returned invalid base64 audio.", exception);
        }
    }

    public static bool ShouldFallbackToLocal(Exception exception)
    {
        if (exception is HttpRequestException httpException)
        {
            return httpException.StatusCode is HttpStatusCode.TooManyRequests or >= HttpStatusCode.InternalServerError;
        }

        return exception is TimeoutException or TaskCanceledException;
    }

    private sealed record GeminiRequest(IReadOnlyList<GeminiContent> Contents, GeminiGenerationConfig GenerationConfig);
    private sealed record GeminiContent(IReadOnlyList<GeminiTextPart> Parts);
    private sealed record GeminiTextPart(string Text);
    private sealed record GeminiGenerationConfig(IReadOnlyList<string> ResponseModalities, GeminiSpeechConfig SpeechConfig);
    private sealed record GeminiSpeechConfig(GeminiVoiceConfig VoiceConfig);
    private sealed record GeminiVoiceConfig(GeminiPrebuiltVoiceConfig PrebuiltVoiceConfig);
    private sealed record GeminiPrebuiltVoiceConfig(string VoiceName);
    private sealed record GeminiResponse(IReadOnlyList<GeminiCandidate>? Candidates);
    private sealed record GeminiCandidate(GeminiResponseContent? Content);
    private sealed record GeminiResponseContent(IReadOnlyList<GeminiResponsePart>? Parts);
    private sealed record GeminiResponsePart(GeminiInlineData? InlineData);
    private sealed record GeminiInlineData(string MimeType, string Data);
}
