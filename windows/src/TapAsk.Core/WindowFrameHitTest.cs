namespace TapAsk.Core;

public enum FrameHit
{
    Client = 1,
    Left = 10,
    Right = 11,
    Top = 12,
    TopLeft = 13,
    TopRight = 14,
    Bottom = 15,
    BottomLeft = 16,
    BottomRight = 17
}

public static class WindowFrameHitTest
{
    public static FrameHit At(int width, int height, int x, int y, int border)
    {
        bool left = x < border, right = x >= width - border;
        bool top = y < border, bottom = y >= height - border;
        if (top && left) return FrameHit.TopLeft;
        if (top && right) return FrameHit.TopRight;
        if (bottom && left) return FrameHit.BottomLeft;
        if (bottom && right) return FrameHit.BottomRight;
        if (left) return FrameHit.Left;
        if (right) return FrameHit.Right;
        if (top) return FrameHit.Top;
        if (bottom) return FrameHit.Bottom;
        return FrameHit.Client;
    }
}
