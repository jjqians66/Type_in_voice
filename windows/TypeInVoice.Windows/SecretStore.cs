using System.Security.Cryptography;
using System.IO;

namespace TypeInVoice.Windows;

internal static class SecretStore
{
    private static readonly string StoreDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "TypeInVoice");

    private static readonly string KeyPath = Path.Combine(StoreDirectory, "api-key.bin");

    internal static string? LoadApiKey()
    {
        try
        {
            if (!File.Exists(KeyPath))
            {
                return null;
            }

            var encrypted = File.ReadAllBytes(KeyPath);
            var plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            return System.Text.Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    internal static void SaveApiKey(string value)
    {
        var trimmed = value.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            if (File.Exists(KeyPath))
            {
                File.Delete(KeyPath);
            }
            return;
        }

        Directory.CreateDirectory(StoreDirectory);
        var plain = System.Text.Encoding.UTF8.GetBytes(trimmed);
        var encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(KeyPath, encrypted);
    }
}
