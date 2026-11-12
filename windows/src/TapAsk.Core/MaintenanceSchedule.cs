namespace TapAsk.Core;

public static class MaintenanceSchedule
{
    public static bool NeedsTimer(bool hasPendingRelease, IEnumerable<(bool Initializing, bool Loading)> pages) =>
        hasPendingRelease || pages.Any(page => page.Initializing || page.Loading);
}
