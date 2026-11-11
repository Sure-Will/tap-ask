using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class UpdateScheduleTests
{
    [Fact]
    public void ChecksOnceADayOnlyWhenEnabled()
    {
        var now = DateTimeOffset.Parse("2026-11-11T00:00:00Z");
        Assert.True(UpdateSchedule.ShouldCheck(true, null, now));
        Assert.False(UpdateSchedule.ShouldCheck(false, null, now));
        Assert.False(UpdateSchedule.ShouldCheck(true, now.AddHours(-23), now));
        Assert.True(UpdateSchedule.ShouldCheck(true, now.AddDays(-1), now));
    }
}
