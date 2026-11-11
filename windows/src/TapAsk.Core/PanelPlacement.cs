namespace TapAsk.Core;

public readonly record struct PanelRect(int X, int Y, int Width, int Height)
{
    public int Right => X + Width;
    public int Bottom => Y + Height;
}

public static class PanelPlacement
{
    public static PanelRect Place(PanelRect preferred, PanelRect screen, PanelRect work, int minimumWidth, int minimumHeight)
    {
        int width = Math.Min(work.Width, Math.Max(minimumWidth, preferred.Width));
        int height = Math.Min(work.Height, Math.Max(minimumHeight, preferred.Height));
        long centerX = (long)preferred.X + preferred.Width / 2;
        long centerY = (long)preferred.Y + preferred.Height / 2;
        bool sameScreen = centerX >= screen.X && centerX < screen.Right && centerY >= screen.Y && centerY < screen.Bottom;
        int x = sameScreen ? preferred.X : work.X + (work.Width - width) / 2;
        int y = sameScreen ? preferred.Y : work.Y + (work.Height - height) / 2;
        return new PanelRect(Math.Clamp(x, work.X, work.Right - width), Math.Clamp(y, work.Y, work.Bottom - height), width, height);
    }
}
