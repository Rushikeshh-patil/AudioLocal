using System.Security.Cryptography;
using System.Text;
using AudioLocal.Windows.Core.Infrastructure;

namespace AudioLocal.Windows.Core.Services;

public interface ISecretStore
{
    Task SaveAsync(string key, string? value, CancellationToken cancellationToken = default);
    Task<string?> ReadAsync(string key, CancellationToken cancellationToken = default);
}

public sealed class DpapiSecretStore : ISecretStore
{
    public async Task SaveAsync(string key, string? value, CancellationToken cancellationToken = default)
    {
        WindowsPaths.EnsureAppFolders();
        var filePath = GetFilePath(key);

        if (string.IsNullOrWhiteSpace(value))
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }

            return;
        }

        var plaintext = Encoding.UTF8.GetBytes(value);
        var protectedBytes = ProtectedData.Protect(plaintext, optionalEntropy: null, DataProtectionScope.CurrentUser);
        await File.WriteAllBytesAsync(filePath, protectedBytes, cancellationToken);
    }

    public async Task<string?> ReadAsync(string key, CancellationToken cancellationToken = default)
    {
        WindowsPaths.EnsureAppFolders();
        var filePath = GetFilePath(key);
        if (!File.Exists(filePath))
        {
            return null;
        }

        var protectedBytes = await File.ReadAllBytesAsync(filePath, cancellationToken);
        var plaintext = ProtectedData.Unprotect(protectedBytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
        return Encoding.UTF8.GetString(plaintext);
    }

    private static string GetFilePath(string key) =>
        Path.Combine(WindowsPaths.SecretsRoot, $"{Sanitize(key)}.bin");

    private static string Sanitize(string key)
    {
        var invalid = Path.GetInvalidFileNameChars();
        return new string(key.Select(character => invalid.Contains(character) ? '_' : character).ToArray());
    }
}
