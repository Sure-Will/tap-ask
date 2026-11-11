namespace TapAsk.Core;

public static class PopupPlacement
{
    public static PanelRect Place(PanelRect parent, PanelRect work, int desiredWidth, int desiredHeight, int gap)
    {
        int width = Math.Min(work.Width, desiredWidth);
        int height = Math.Min(work.Height, desiredHeight);
        int right = parent.Right + gap;
        int left = parent.X - gap - width;
        int x = right >= work.X && right + width <= work.Right ? right
            : left >= work.X && left + width <= work.Right ? left
            : parent.X + (parent.Width - width) / 2;
        return new PanelRect(Math.Clamp(x, work.X, work.Right - width),
            Math.Clamp(parent.Y, work.Y, work.Bottom - height), width, height);
    }
}
