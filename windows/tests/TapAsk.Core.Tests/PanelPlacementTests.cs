using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class PanelPlacementTests
{
    [Fact]
    public void SameScreenKeepsPositionAndClampsToWorkingArea()
    {
        var result = PanelPlacement.Place(new PanelRect(1600, 700, 480, 720),
            new PanelRect(0, 0, 1920, 1080), new PanelRect(0, 0, 1920, 1040), 360, 480);
        Assert.Equal(new PanelRect(1440, 320, 480, 720), result);
    }

    [Fact]
    public void ChangedScreenCentersAndShrinksToSmallWorkingArea()
    {
        var result = PanelPlacement.Place(new PanelRect(100, 100, 800, 900),
            new PanelRect(1920, 0, 320, 400), new PanelRect(1920, 0, 320, 380), 360, 480);
        Assert.Equal(new PanelRect(1920, 0, 320, 380), result);
    }
}
