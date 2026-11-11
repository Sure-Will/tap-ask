using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace TapAsk;

// Only the 60x20 hit area sits above the webpage; its background is almost transparent.
internal sealed class DragHandleForm(Form owner) : LayeredOverlayForm(owner)
{
    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left) MovePanel(2); // HTCAPTION
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Cursor = Cursors.Hand;
    }

    public override void UpdatePosition()
    {
        if (!IsHandleCreated || !Panel.Visible) return;
        float scale = Panel.DeviceDpi / 96f;
        int width = (int)Math.Round(60 * scale);
        int height = (int)Math.Round(20 * scale);
        var position = Panel.PointToScreen(new Point((Panel.ClientSize.Width - width) / 2, (int)Math.Round(2 * scale)));

        using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.FromArgb(1, 0, 0, 0));
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float barWidth = 36 * scale, barHeight = 4 * scale;
            float x = (width - barWidth) / 2, y = (height - barHeight) / 2;
            using var shadow = new SolidBrush(Color.FromArgb(55, 0, 0, 0));
            using var white = new SolidBrush(Color.FromArgb(217, 255, 255, 255));
            FillCapsule(graphics, shadow, x, y + scale, barWidth, barHeight);
            FillCapsule(graphics, white, x, y, barWidth, barHeight);
        }
        SetBitmap(bitmap, position);
    }

    private static void FillCapsule(Graphics graphics, Brush brush, float x, float y, float width, float height)
    {
        using var path = new GraphicsPath();
        path.AddArc(x, y, height, height, 90, 180);
        path.AddArc(x + width - height, y, height, height, 270, 180);
        path.CloseFigure();
        graphics.FillPath(brush, path);
    }
}
