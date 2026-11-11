using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class PageLoadDeadlineTests
{
    [Fact]
    public void RedirectDoesNotExtendTimeoutButANewAttemptGetsItsOwnDeadline()
    {
        var deadline = new PageLoadDeadline();
        deadline.Start(TimeSpan.Zero);
        deadline.Start(TimeSpan.FromSeconds(15));
        Assert.False(deadline.HasExpired(TimeSpan.FromSeconds(19)));
        Assert.True(deadline.HasExpired(TimeSpan.FromSeconds(20)));
        deadline.Finish();
        Assert.False(deadline.HasExpired(TimeSpan.FromSeconds(21)));
        deadline.Start(TimeSpan.FromSeconds(21));
        Assert.True(deadline.HasExpired(TimeSpan.FromSeconds(41)));
    }
}
