namespace TapAsk.Core;

public enum NavigationDecision { Allow, Download, Browser, Cancel }

public sealed class NavigationPolicy
{
    private readonly HashSet<string> providerHosts;
    private readonly HashSet<string> panelHosts;

    public Provider Provider { get; }

    public NavigationPolicy(Provider provider, IEnumerable<string> identityHosts)
    {
        Provider = provider;
        providerHosts = new(provider.Hosts, StringComparer.OrdinalIgnoreCase);
        panelHosts = new(providerHosts, StringComparer.OrdinalIgnoreCase);
        panelHosts.UnionWith(identityHosts);
    }

    public static bool IsHttps(Uri? url)
    {
        if (url is not { IsAbsoluteUri: true } || url.Scheme != Uri.UriSchemeHttps ||
            string.IsNullOrEmpty(url.Host) || url.Port != 443 || !string.IsNullOrEmpty(url.UserInfo))
            return false;

        // Uri.UserInfo is empty for an explicitly empty user name; reject the authority too.
        var original = url.OriginalString;
        var start = original.IndexOf("://", StringComparison.Ordinal);
        if (start < 0) return false;
        var authority = original[(start + 3)..].Split('/', '?', '#')[0];
        return !authority.Contains('@');
    }

    public bool IsPanelUrl(Uri? url) => IsHttps(url) && panelHosts.Contains(url!.IdnHost);
    public bool IsProviderUrl(Uri? url) => IsHttps(url) && providerHosts.Contains(url!.IdnHost);
    public static bool IsGeneratedFile(Uri? url) => url is { IsAbsoluteUri: true } &&
        (url.Scheme.Equals("blob", StringComparison.OrdinalIgnoreCase) ||
         url.Scheme.Equals("data", StringComparison.OrdinalIgnoreCase));

    private static bool IsFrameUrl(Uri? url) => IsHttps(url) ||
        url?.OriginalString is "about:blank" or "about:srcdoc";

    public NavigationDecision Action(Uri? url, bool topLevel, bool clickedLink, string? method,
                                     bool wantsDownload, Uri? sourceUrl)
    {
        var generated = IsGeneratedFile(url);
        if (wantsDownload || (topLevel && generated))
            return IsPanelUrl(sourceUrl) && (IsHttps(url) || generated)
                ? NavigationDecision.Download : NavigationDecision.Cancel;
        if (!topLevel) return IsFrameUrl(url) ? NavigationDecision.Allow : NavigationDecision.Cancel;
        if (IsPanelUrl(url)) return NavigationDecision.Allow;
        if (clickedLink && string.Equals(method ?? "GET", "GET", StringComparison.OrdinalIgnoreCase) &&
            IsPanelUrl(sourceUrl) && IsHttps(url)) return NavigationDecision.Browser;
        return NavigationDecision.Cancel;
    }

    public NavigationDecision Response(Uri? url, bool mainFrame, bool canDisplay, bool attachment)
    {
        if (!canDisplay || attachment)
            return IsHttps(url) || IsGeneratedFile(url) ? NavigationDecision.Download : NavigationDecision.Cancel;
        if (mainFrame) return IsPanelUrl(url) ? NavigationDecision.Allow : NavigationDecision.Cancel;
        return IsFrameUrl(url) ? NavigationDecision.Allow : NavigationDecision.Cancel;
    }

    public static string Origin(Uri? url)
    {
        if (url is not { IsAbsoluteUri: true } || string.IsNullOrEmpty(url.Host))
            return "无有效网站来源";
        // OriginalString preserves explicit default ports, which Uri otherwise normalizes away.
        var authority = url.OriginalString[(url.OriginalString.IndexOf("://", StringComparison.Ordinal) + 3)..]
            .Split('/', '?', '#')[0];
        var hasPort = authority[(authority.LastIndexOf('@') + 1)..].Contains(':');
        return $"{url.Scheme.ToLowerInvariant()}://{url.IdnHost.ToLowerInvariant()}" +
               (hasPort ? $":{url.Port}" : "");
    }
}
