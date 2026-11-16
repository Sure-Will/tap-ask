using System.Runtime.InteropServices;
using System.Text;
using TapAsk;
using Xunit;

namespace TapAsk.WindowsTests;

public class NativeTrayMenuTests
{
    private const uint MfByPosition = 0x400, MfChecked = 8, MfGrayed = 1, MfSeparator = 0x800;

    [Fact]
    public void NativeMenuPreservesStateDispatchAndReleasesItsHandle()
    {
        int selected = 0;
        TrayMenuItem[] items =
        [
            new("Chat & AI", () => selected = 1, Checked: true, Shortcut: "Ctrl+1"),
            TrayMenuItem.Separator,
            new("更新已下载", Enabled: false),
            new("立即安装并重启", () => selected = 2)
        ];
        using var menu = NativeTrayMenu.Build(items, out var actions);
        var handle = menu.DangerousGetHandle();
        Assert.True(IsMenu(handle));
        Assert.Equal(4, GetMenuItemCount(handle));
        Assert.NotEqual(0u, GetMenuState(handle, 0, MfByPosition) & MfChecked);
        Assert.NotEqual(0u, GetMenuState(handle, 1, MfByPosition) & MfSeparator);
        Assert.NotEqual(0u, GetMenuState(handle, 2, MfByPosition) & MfGrayed);
        var title = new StringBuilder(128);
        Assert.True(GetMenuString(handle, 0, title, title.Capacity, MfByPosition) > 0);
        Assert.Equal("Chat && AI\tCtrl+1", title.ToString());
        Assert.False(actions.ContainsKey(GetMenuItemID(handle, 2)));
        actions[GetMenuItemID(handle, 3)]();
        Assert.Equal(2, selected);
        menu.Dispose();
        Assert.False(IsMenu(handle));
    }

    [Theory]
    [InlineData(1, 2, 2, true)]
    [InlineData(1, 2, 3, false)]
    [InlineData(0, 2, 2, false)]
    [InlineData(2, 2, 2, false)]
    public void FocusReturnsOnlyWhenTheMenuStillOwnsIt(int previous, int owner, int current, bool expected)
    {
        Assert.Equal(expected, NativeTrayMenu.ShouldRestoreFocus(new IntPtr(previous), new IntPtr(owner), new IntPtr(current)));
    }

    [DllImport("user32.dll")]
    private static extern bool IsMenu(IntPtr menu);
    [DllImport("user32.dll")]
    private static extern int GetMenuItemCount(IntPtr menu);
    [DllImport("user32.dll")]
    private static extern uint GetMenuState(IntPtr menu, uint item, uint flags);
    [DllImport("user32.dll")]
    private static extern uint GetMenuItemID(IntPtr menu, int position);
    [DllImport("user32.dll", EntryPoint = "GetMenuStringW", CharSet = CharSet.Unicode)]
    private static extern int GetMenuString(IntPtr menu, uint item, StringBuilder text, int maxCount, uint flags);
}
