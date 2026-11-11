using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class NavigationNoticeGateTests
{
    [Fact]
    public void SuppressesSameHostAndKindForTenSecondsButNotOtherHosts()
    {
        var gate = new NavigationNoticeGate();
        Assert.True(gate.ShouldShow("blocked", "EXAMPLE.COM", TimeSpan.Zero));
        Assert.False(gate.ShouldShow("blocked", "example.com", TimeSpan.FromSeconds(9)));
        Assert.True(gate.ShouldShow("blocked", "other.com", TimeSpan.FromSeconds(9)));
        Assert.True(gate.ShouldShow("blocked", "example.com", TimeSpan.FromSeconds(10)));
    }
}
