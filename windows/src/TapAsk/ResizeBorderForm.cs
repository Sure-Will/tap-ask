using System.Drawing.Imaging;
using TapAsk.Core;

namespace TapAsk;

// WebView2 owns its child HWND, so a transparent edge receives native resize gestures.
internal sealed class ResizeBorderForm(Form owner) : LayeredOverlayForm(owner)
{
    private Size lastSize;
    private int lastBorder;

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        Cursor = Hit(e.Location) switch
        {
            FrameHit.Left or FrameHit.Right => Cursors.SizeWE,
            FrameHit.Top or FrameHit.Bottom => Cursors.SizeNS,
            FrameHit.TopLeft or FrameHit.BottomRight => Cursors.SizeNWSE,
            FrameHit.TopRight or FrameHit.BottomLeft => Cursors.SizeNESW,
            _ => Cursors.Default
        };
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        var hit = Hit(e.Location);
        if (e.Button == MouseButtons.Left && hit != FrameHit.Client) MovePanel((int)hit);
    }

    public override void UpdatePosition()
    {
        if (!IsHandleCreated || !Panel.Visible || Panel.ClientSize.Width <= 0 || Panel.ClientSize.Height <= 0) return;
        int width = Panel.ClientSize.Width, height = Panel.ClientSize.Height, border = Border;
        var position = Panel.PointToScreen(Point.Empty);
        if (lastSize == Panel.ClientSize && lastBorder == border)
        {
            MoveOverlay(position);
            return;
        }
        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        using (var edge = new SolidBrush(Color.FromArgb(1, 0, 0, 0)))
        {
            graphics.Clear(Color.Transparent);
            graphics.FillRectangle(edge, 0, 0, width, border);
            graphics.FillRectangle(edge, 0, height - border, width, border);
            graphics.FillRectangle(edge, 0, border, border, height - 2 * border);
            graphics.FillRectangle(edge, width - border, border, border, height - 2 * border);
        }
        SetBitmap(bitmap, position);
        lastSize = Panel.ClientSize;
        lastBorder = border;
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        lastSize = Size.Empty;
        base.OnHandleDestroyed(e);
    }

    private int Border => Math.Max(1, (int)Math.Round(6 * Panel.DeviceDpi / 96.0));
    private FrameHit Hit(Point point) => WindowFrameHitTest.At(Panel.ClientSize.Width, Panel.ClientSize.Height, point.X, point.Y, Border);
}
