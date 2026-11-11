using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class WindowFrameHitTestTests
{
    [Theory]
    [InlineData(0, 0, FrameHit.TopLeft)]
    [InlineData(479, 0, FrameHit.TopRight)]
    [InlineData(0, 719, FrameHit.BottomLeft)]
    [InlineData(479, 719, FrameHit.BottomRight)]
    [InlineData(2, 100, FrameHit.Left)]
    [InlineData(478, 100, FrameHit.Right)]
    [InlineData(100, 2, FrameHit.Top)]
    [InlineData(100, 718, FrameHit.Bottom)]
    [InlineData(240, 12, FrameHit.Client)]
    [InlineData(6, 6, FrameHit.Client)]
    public void IdentifiesResizeEdgesWithoutTakingWebContent(int x, int y, FrameHit expected) =>
        Assert.Equal(expected, WindowFrameHitTest.At(480, 720, x, y, 6));
}
