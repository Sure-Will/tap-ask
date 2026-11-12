using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class MaintenanceScheduleTests
{
    [Fact]
    public void TimerRunsOnlyForPendingReleaseOrUnfinishedPage()
    {
        Assert.False(MaintenanceSchedule.NeedsTimer(false, []));
        Assert.False(MaintenanceSchedule.NeedsTimer(false, [(false, false)]));
        Assert.True(MaintenanceSchedule.NeedsTimer(true, [(false, false)]));
        Assert.True(MaintenanceSchedule.NeedsTimer(false, [(true, false)]));
        Assert.True(MaintenanceSchedule.NeedsTimer(false, [(false, false), (false, true)]));
    }
}
