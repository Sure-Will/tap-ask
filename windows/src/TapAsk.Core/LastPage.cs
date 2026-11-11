using System.Text.RegularExpressions;

namespace TapAsk.Core;

public static partial class LastPage
{
    public static string? Saved(Uri? url, NavigationPolicy policy)
    {
        if (!policy.IsProviderUrl(url) ||
            !string.Equals(url!.IdnHost, policy.Provider.Home.IdnHost, StringComparison.OrdinalIgnoreCase))
            return null;
        return $"https://{url.IdnHost.ToLowerInvariant()}{url.AbsolutePath}";
    }

    public static Uri? Restored(string? value, NavigationPolicy policy)
    {
        if (string.IsNullOrWhiteSpace(value) || InvalidUrlCharacters().IsMatch(value) ||
            !Uri.TryCreate(value, UriKind.Absolute, out var url)) return null;
        var saved = Saved(url, policy);
        return saved is null ? null : new Uri(saved);
    }

    [GeneratedRegex(@"%(?![0-9A-Fa-f]{2})|[\x00-\x20]")]
    private static partial Regex InvalidUrlCharacters();
}
