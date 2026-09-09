using System.Net.Http.Headers;
using System.Net.Http;

namespace TypeInVoice.Windows;

internal sealed class TranscriptionService
{
    private static readonly HttpClient Client = new()
    {
        BaseAddress = new Uri("https://api.openai.com/"),
        Timeout = TimeSpan.FromSeconds(90)
    };

    internal async Task<string> TranscribeAsync(
        byte[] wavAudio,
        string apiKey,
        string languageCode,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "v1/audio/transcriptions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

        using var form = new MultipartFormDataContent();
        using var audio = new ByteArrayContent(wavAudio);
        audio.Headers.ContentType = new MediaTypeHeaderValue("audio/wav");
        form.Add(audio, "file", "dictation.wav");
        form.Add(new StringContent("whisper-1"), "model");
        form.Add(new StringContent("text"), "response_format");
        if (!string.Equals(languageCode, "auto", StringComparison.OrdinalIgnoreCase))
        {
            form.Add(new StringContent(languageCode), "language");
        }
        request.Content = form;

        using var response = await Client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var detail = response.StatusCode switch
            {
                System.Net.HttpStatusCode.Unauthorized => "The OpenAI API key was rejected.",
                System.Net.HttpStatusCode.TooManyRequests => "OpenAI rate limit reached. Please try again shortly.",
                _ => $"OpenAI returned {(int)response.StatusCode} ({response.ReasonPhrase})."
            };
            throw new InvalidOperationException(detail);
        }

        var text = body.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new InvalidOperationException("No speech was detected.");
        }
        return text;
    }
}
