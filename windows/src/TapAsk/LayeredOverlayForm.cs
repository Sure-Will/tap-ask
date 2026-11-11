using System.Runtime.InteropServices;

namespace TapAsk;

internal abstract class LayeredOverlayForm : Form
{
    protected LayeredOverlayForm(Form owner)
    {
        Panel = owner;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.None;
    }

    protected Form Panel { get; }
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var value = base.CreateParams;
            value.ExStyle |= 0x00000080 | 0x00080000 | 0x08000000; // tool window, layered, no activation
            return value;
        }
    }

    public abstract void UpdatePosition();

    protected void MovePanel(int hit)
    {
        ReleaseCapture();
        SendMessage(Panel.Handle, 0x00A1, new IntPtr(hit), IntPtr.Zero); // WM_NCLBUTTONDOWN
    }

    protected void SetBitmap(Bitmap bitmap, Point position)
    {
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr memory = CreateCompatibleDC(screen);
        IntPtr image = bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr previous = SelectObject(memory, image);
        try
        {
            var destination = new NativePoint(position.X, position.Y);
            var source = new NativePoint(0, 0);
            var size = new NativeSize(bitmap.Width, bitmap.Height);
            var blend = new BlendFunction { SourceConstantAlpha = 255, AlphaFormat = 1 };
            if (!UpdateLayeredWindow(Handle, screen, ref destination, ref size, memory, ref source, 0, ref blend, 2))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            SelectObject(memory, previous);
            DeleteObject(image);
            DeleteDC(memory);
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    protected void MoveOverlay(Point position) =>
        SetWindowPos(Handle, IntPtr.Zero, position.X, position.Y, 0, 0, 0x0001 | 0x0004 | 0x0010);

    [StructLayout(LayoutKind.Sequential)] private readonly record struct NativePoint(int X, int Y);
    [StructLayout(LayoutKind.Sequential)] private readonly record struct NativeSize(int Width, int Height);
    [StructLayout(LayoutKind.Sequential, Pack = 1)] private struct BlendFunction
    {
        public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat;
    }

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr item);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr item);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UpdateLayeredWindow(
        IntPtr window, IntPtr destinationDc, ref NativePoint destination, ref NativeSize size,
        IntPtr sourceDc, ref NativePoint source, int colorKey, ref BlendFunction blend, int flags);
}
