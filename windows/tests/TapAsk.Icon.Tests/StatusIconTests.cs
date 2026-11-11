using TapAsk;
using Xunit;

namespace TapAsk.WindowsTests;

public sealed class StatusIconTests
{
    [Theory]
    [InlineData(255)]
    [InlineData(32)]
    public void TrayIconRendersMacMarkWithTransparentCutouts(int tone)
    {
        using var icon = StatusIcon.Create(Color.FromArgb(tone, tone, tone));
        using var image = icon.ToBitmap();
        Assert.Equal(64, image.Width);
        Assert.Equal(64, image.Height);
        Assert.Equal(0, image.GetPixel(0, 0).A);       // outside the mark
        Assert.Equal(0, image.GetPixel(20, 26).A);     // gap around the inner window
        Assert.Equal(0, image.GetPixel(32, 28).A);     // star
        Assert.Equal(0, image.GetPixel(32, 39).A);     // input slot
        Assert.Equal(Color.FromArgb(255, tone, tone, tone).ToArgb(), image.GetPixel(9, 32).ToArgb());
        Assert.Equal(Color.FromArgb(255, tone, tone, tone).ToArgb(), image.GetPixel(24, 32).ToArgb());
    }
}
