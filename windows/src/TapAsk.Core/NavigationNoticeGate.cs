namespace TapAsk.Core;

public sealed class NavigationNoticeGate
{
    private readonly Dictionary<(string Kind, string Host), TimeSpan> shown = new();

    public bool ShouldShow(string kind, string host, TimeSpan now)
    {
        var key = (kind, host.ToLowerInvariant());
        if (shown.TryGetValue(key, out var previous) && now - previous < TimeSpan.FromSeconds(10)) return false;
        foreach (var expired in shown.Where(entry => now - entry.Value >= TimeSpan.FromSeconds(10)).Select(entry => entry.Key).ToArray())
            shown.Remove(expired);
        shown[key] = now;
        return true;
    }
}
