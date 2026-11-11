namespace TapAsk.Core;

// Timestamps are monotonic elapsed time, not wall-clock time.
public sealed class SessionRetentionPolicy
{
    public static readonly TimeSpan BackgroundLifetime = TimeSpan.FromSeconds(300);
    public string? CurrentProviderId { get; private set; }
    private string? backgroundProviderId;
    public TimeSpan? NextExpiration { get; private set; }

    public string? DidDisplay(string providerId, TimeSpan now)
    {
        if (CurrentProviderId == providerId) return null;
        var released = backgroundProviderId == providerId ? null : backgroundProviderId;
        backgroundProviderId = CurrentProviderId;
        NextExpiration = backgroundProviderId is null ? null : now + BackgroundLifetime;
        CurrentProviderId = providerId;
        return released;
    }

    public string? Expire(TimeSpan now) => NextExpiration is { } deadline && now >= deadline
        ? ReleaseBackground() : null;

    public string? ReleaseBackground()
    {
        var released = backgroundProviderId;
        backgroundProviderId = null;
        NextExpiration = null;
        return released;
    }
}
