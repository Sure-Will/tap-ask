namespace TapAsk.Core;

public sealed class PageLoadDeadline
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(20);
    private TimeSpan? startedAt;

    // Redirects are part of the same attempt and do not extend its deadline.
    public void Start(TimeSpan now) => startedAt ??= now;
    public void Finish() => startedAt = null;
    public bool HasExpired(TimeSpan now) => startedAt is { } start && now - start >= Timeout;
}
