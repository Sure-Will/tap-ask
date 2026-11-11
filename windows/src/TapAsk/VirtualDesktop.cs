using System.Runtime.InteropServices;

namespace TapAsk;

internal static class VirtualDesktop
{
    public static void MoveToForegroundDesktop(IntPtr window, IntPtr foreground)
    {
        if (foreground == IntPtr.Zero || foreground == window) return;
        var manager = (IVirtualDesktopManager)new VirtualDesktopManager();
        try
        {
            if (!manager.IsWindowOnCurrentVirtualDesktop(window) && manager.IsWindowOnCurrentVirtualDesktop(foreground))
            {
                manager.GetWindowDesktopId(foreground, out var desktop);
                manager.MoveWindowToDesktop(window, ref desktop);
            }
        }
        finally { Marshal.ReleaseComObject(manager); }
    }

    [ComImport, Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")]
    private class VirtualDesktopManager;

    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        [return: MarshalAs(UnmanagedType.Bool)] bool IsWindowOnCurrentVirtualDesktop(IntPtr window);
        void GetWindowDesktopId(IntPtr window, out Guid desktopId);
        void MoveWindowToDesktop(IntPtr window, ref Guid desktopId);
    }
}
