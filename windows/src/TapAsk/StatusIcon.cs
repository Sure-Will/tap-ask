using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace TapAsk;

// Same 22 × 18 geometry and even-odd cutouts as macOS TapAskCore/BrandMark.swift.
internal static class StatusIcon
{
    public static Icon Create()
    {
        using var personalize = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        var color = personalize?.GetValue("SystemUsesLightTheme") is int light && light != 0
            ? Color.FromArgb(32, 32, 32) : Color.White;
        return Create(color);
    }

    internal static Icon Create(Color color)
    {
        const int size = 64;
        using var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.ScaleTransform(size / 22f, size / 22f);
        graphics.TranslateTransform(0, 2);
        using var path = new GraphicsPath(FillMode.Alternate);
        AddRoundedRectangle(path, 1, 2.5f, 20, 13, 2.4f);
        AddRoundedRectangle(path, 6.6f, 3.7f, 8.8f, 10.6f, 1.8f);
        AddRoundedRectangle(path, 7.8f, 4.9f, 6.4f, 8.2f, 1);
        AddRoundedRectangle(path, 8.7f, 10.6f, 4.6f, 1.5f, 0.75f);
        AddStar(path);
        using var brush = new SolidBrush(color);
        graphics.FillPath(brush, path);
        var handle = bitmap.GetHicon();
        try { return (Icon)Icon.FromHandle(handle).Clone(); }
        finally { DestroyIcon(handle); }
    }

    private static void AddRoundedRectangle(GraphicsPath path, float x, float y, float width, float height, float radius)
    {
        float diameter = radius * 2;
        path.StartFigure();
        path.AddArc(x, y, diameter, diameter, 180, 90);
        path.AddArc(x + width - diameter, y, diameter, diameter, 270, 90);
        path.AddArc(x + width - diameter, y + height - diameter, diameter, diameter, 0, 90);
        path.AddArc(x, y + height - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
    }

    private static void AddStar(GraphicsPath path)
    {
        var top = new PointF(11, 5.9f);
        var right = new PointF(12.8f, 7.8f);
        var bottom = new PointF(11, 9.7f);
        var left = new PointF(9.2f, 7.8f);
        path.StartFigure();
        AddQuadratic(path, top, new PointF(11.3f, 7.5f), right);
        AddQuadratic(path, right, new PointF(11.3f, 8.1f), bottom);
        AddQuadratic(path, bottom, new PointF(10.7f, 8.1f), left);
        AddQuadratic(path, left, new PointF(10.7f, 7.5f), top);
        path.CloseFigure();
    }

    private static void AddQuadratic(GraphicsPath path, PointF start, PointF control, PointF end)
    {
        var first = new PointF(start.X + (control.X - start.X) * 2 / 3, start.Y + (control.Y - start.Y) * 2 / 3);
        var second = new PointF(end.X + (control.X - end.X) * 2 / 3, end.Y + (control.Y - end.Y) * 2 / 3);
        path.AddBezier(start, first, second, end);
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);
}
