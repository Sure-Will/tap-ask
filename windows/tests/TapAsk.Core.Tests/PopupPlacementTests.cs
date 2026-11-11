using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class PopupPlacementTests
{
    [Fact]
    public void PrefersRightThenLeftAndKeepsPopupInWorkArea()
    {
        var work = new PanelRect(0, 0, 1920, 1040);
        Assert.Equal(new PanelRect(592, 100, 480, 640), PopupPlacement.Place(new PanelRect(100, 100, 480, 720), work, 480, 640, 12));
        Assert.Equal(new PanelRect(1008, 400, 480, 640), PopupPlacement.Place(new PanelRect(1500, 700, 400, 500), work, 480, 640, 12));
    }

    [Fact]
    public void SmallScreenTakesPrecedenceOverDesiredSize()
    {
        Assert.Equal(new PanelRect(0, 0, 300, 400), PopupPlacement.Place(new PanelRect(0, 0, 300, 400), new PanelRect(0, 0, 300, 400), 480, 640, 12));
    }
}
