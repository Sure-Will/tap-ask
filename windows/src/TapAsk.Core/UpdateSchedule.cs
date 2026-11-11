namespace TapAsk.Core;

public static class UpdateSchedule
{
    public static bool ShouldCheck(bool enabled, DateTimeOffset? lastCheck, DateTimeOffset now) =>
        enabled && (lastCheck is null || now - lastCheck.Value >= TimeSpan.FromDays(1));
}
