using System.IO;

namespace TypeInVoice.Windows;

internal static class PreferenceStore
{
    private static readonly HashSet<string> SupportedLanguages =
        new(StringComparer.OrdinalIgnoreCase) { "auto", "en", "zh", "ja", "ko", "es", "fr", "de" };

    private static readonly string StoreDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "TypeInVoice");

    private static readonly string LanguagePath = Path.Combine(StoreDirectory, "language.txt");

    internal static string LoadLanguage()
    {
        try
        {
            var value = File.Exists(LanguagePath) ? File.ReadAllText(LanguagePath).Trim() : "auto";
            return SupportedLanguages.Contains(value) ? value.ToLowerInvariant() : "auto";
        }
        catch (IOException)
        {
            return "auto";
        }
    }

    internal static void SaveLanguage(string value)
    {
        var normalized = SupportedLanguages.Contains(value) ? value.ToLowerInvariant() : "auto";
        Directory.CreateDirectory(StoreDirectory);
        File.WriteAllText(LanguagePath, normalized);
    }
}
