namespace TapAsk.Core;

public static class ExternalLinkContext
{
    public static Uri? BrowserUrl(NavigationPolicy policy, bool hasLink, string? link, string? frame)
    {
        if (!hasLink || !Uri.TryCreate(link, UriKind.Absolute, out var destination) ||
            !Uri.TryCreate(frame, UriKind.Absolute, out var source)) return null;
        return policy.Action(destination, true, true, "GET", false, source) == NavigationDecision.Browser
            ? destination : null;
    }
}
