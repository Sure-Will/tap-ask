using System.Runtime.ExceptionServices;
using TapAsk;
using Xunit;

namespace TapAsk.WindowsTests;

public class InfoOverlayTests
{
    [Fact]
    public void OverlayStaysWithinOwnerAndRetryRemainsUsable()
    {
        Exception? failure = null;
        bool clicked = false;
        var thread = new Thread(() =>
        {
            try
            {
                using var owner = new Form { ShowInTaskbar = false, StartPosition = FormStartPosition.Manual,
                    Location = new Point(-3000, -3000), ClientSize = new Size(360, 480) };
                owner.Show();
                using var overlay = new InfoOverlayForm(owner, centered: true, retry: () => clicked = true);
                overlay.InitializeOverlay();
                overlay.SetContent("网页加载失败", show: true, canRetry: true);
                Assert.True(overlay.Visible);
                Assert.True(owner.RectangleToScreen(owner.ClientRectangle).Contains(overlay.Bounds));
                overlay.Controls.OfType<Button>().Single().PerformClick();
                Assert.True(clicked);
                overlay.SetContent("", show: false);
                Assert.False(overlay.Visible);
            }
            catch (Exception ex) { failure = ex; }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Overlay interaction did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
