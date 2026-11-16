using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace TapAsk;

internal sealed record TrayMenuItem(string? Title, Action? OnClick = null, bool Checked = false,
                                    bool Enabled = true, string? Shortcut = null)
{
    public static TrayMenuItem Separator { get; } = new(Title: null);
}

internal sealed class NativeTrayMenu : NativeWindow, IDisposable
{
    private const uint MfString = 0, MfGrayed = 1, MfChecked = 8, MfSeparator = 0x800;
    private const uint TpmReturnCommand = 0x100, TpmRightButton = 2, TpmRightAlign = 8, TpmBottomAlign = 0x20;

    public NativeTrayMenu() => CreateHandle(new CreateParams());

    public Action? Show(Point anchor, IReadOnlyList<TrayMenuItem> items)
    {
        uint selected;
        Dictionary<uint, Action> actions;
        using (var menu = Build(items, out actions))
        {
            var previous = GetForegroundWindow();
            if (!SetForegroundWindow(Handle))
                throw new InvalidOperationException("无法激活托盘菜单。");
            try
            {
                selected = TrackPopupMenuEx(menu, TpmReturnCommand | TpmRightButton | TpmRightAlign | TpmBottomAlign,
                                            anchor.X, anchor.Y, Handle, IntPtr.Zero);
            }
            finally
            {
                bool posted = PostMessage(Handle, 0, IntPtr.Zero, IntPtr.Zero);
                int postError = posted ? 0 : Marshal.GetLastWin32Error();
                if (ShouldRestoreFocus(previous, Handle, GetForegroundWindow()) &&
                    IsWindow(previous) && IsWindowVisible(previous) && !IsIconic(previous) && !SetForegroundWindow(previous))
                    NavigationLog.Write("app", "tray-menu-focus", null, "restore-failed");
                if (!posted) throw new Win32Exception(postError);
            }
        }
        return actions.GetValueOrDefault(selected);
    }

    internal static bool ShouldRestoreFocus(IntPtr previous, IntPtr owner, IntPtr current) =>
        previous != IntPtr.Zero && previous != owner && current == owner;

    internal static MenuHandle Build(IReadOnlyList<TrayMenuItem> items, out Dictionary<uint, Action> actions)
    {
        var raw = CreatePopupMenu();
        if (raw == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        var menu = new MenuHandle(raw);
        actions = new Dictionary<uint, Action>();
        try
        {
            uint id = 1;
            foreach (var item in items)
            {
                if (item.Title is null)
                {
                    if (!AppendMenu(menu, MfSeparator, UIntPtr.Zero, null))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    continue;
                }
                uint flags = MfString | (item.Checked ? MfChecked : 0) | (item.Enabled ? 0 : MfGrayed);
                string title = item.Title.Replace("&", "&&", StringComparison.Ordinal);
                if (!string.IsNullOrEmpty(item.Shortcut)) title += "\t" + item.Shortcut.Replace("&", "&&", StringComparison.Ordinal);
                if (!AppendMenu(menu, flags, new UIntPtr(id), title))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if (item.Enabled && item.OnClick is not null) actions.Add(id, item.OnClick);
                id++;
            }
            return menu;
        }
        catch { menu.Dispose(); throw; }
    }

    public void Dispose() => DestroyHandle();

    internal sealed class MenuHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public MenuHandle(IntPtr handle) : base(true) => SetHandle(handle);
        protected override bool ReleaseHandle() => DestroyMenu(handle);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool AppendMenu(MenuHandle menu, uint flags, UIntPtr item, string? text);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint TrackPopupMenuEx(MenuHandle menu, uint flags, int x, int y, IntPtr owner, IntPtr parameters);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
