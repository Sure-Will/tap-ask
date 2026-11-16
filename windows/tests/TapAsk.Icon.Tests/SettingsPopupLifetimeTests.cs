using System.Reflection;
using System.Runtime.ExceptionServices;
using TapAsk;
using TapAsk.Core;
using Xunit;

namespace TapAsk.WindowsTests;

[Collection("Desktop UI")]
public class SettingsPopupLifetimeTests
{
    [Theory]
    [InlineData("调整服务商顺序…", "保存")]
    [InlineData("调整服务商顺序…", "取消")]
    [InlineData("调整服务商顺序…", "失焦")]
    [InlineData("设置快捷键…", "保存")]
    [InlineData("设置快捷键…", "取消")]
    [InlineData("设置快捷键…", "失焦")]
    public void ClosingSettingsFromTheTrayDoesNotDisposeWhileClosing(string menuTitle, string buttonTitle)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string path = Path.Combine(Path.GetTempPath(), $"tapask-popup-lifetime-{Guid.NewGuid():N}.json");
            var errors = new List<Exception>();
            ThreadExceptionEventHandler listener = (_, e) => errors.Add(e.Exception);
            Application.ThreadException += listener;
            try
            {
                Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"]),
                    new("second", "Second", new Uri("https://second.invalid/"), ["second.invalid"])];
                var store = new SettingsStore(path);
                store.SaveGlobalShortcut(new GlobalShortcut((uint)Keys.F24,
                    ShortcutModifiers.Control | ShortcutModifiers.Alt | ShortcutModifiers.Shift));
                using var owner = new MainForm(settingsStore: store, providerCatalog: new([], providers));
                // The tray lifecycle can be exercised without creating a WebView profile.
                typeof(MainForm).GetField("environmentStarted", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(owner, true);
                _ = owner.Handle;

                var screen = Screen.PrimaryScreen!.WorkingArea;
                var anchor = new Point(screen.Right - 20, screen.Bottom - 20);
                Assert.Single(owner.BuildMenu(anchor), item => item.Title == menuTitle).OnClick!();
                Application.DoEvents();

                var field = typeof(MainForm).GetField("settingsPopup", BindingFlags.Instance | BindingFlags.NonPublic)!;
                var popup = Assert.IsType<SettingsPopup>(field.GetValue(owner));
                Assert.True(popup.Visible);
                Assert.True(popup.AutoClose);
                var host = Assert.Single(popup.Items.OfType<ToolStripControlHost>());
                var form = Assert.IsAssignableFrom<Form>(host.Control);
                if (buttonTitle == "失焦")
                {
                    popup.Close(ToolStripDropDownCloseReason.AppFocusChange);
                }
                else
                {
                    // These controls are driven directly, independently of other desktop windows.
                    popup.AutoClose = false;
                    if (form is ProviderOrderForm)
                    {
                        var list = Assert.Single(form.Controls.OfType<ListBox>());
                        var onKeyDown = typeof(Control).GetMethod("OnKeyDown", BindingFlags.Instance | BindingFlags.NonPublic)!;
                        onKeyDown.Invoke(list, [new KeyEventArgs(Keys.Alt | Keys.Down)]);
                    }
                    var buttons = Assert.Single(form.Controls.OfType<FlowLayoutPanel>());
                    Assert.Single(buttons.Controls.OfType<Button>(), button => button.Text == buttonTitle).PerformClick();
                }
                Application.DoEvents();

                Assert.Empty(errors);
                Assert.True(popup.IsDisposed);
                Assert.Null(field.GetValue(owner));
                if (menuTitle == "调整服务商顺序…")
                    Assert.Equal(buttonTitle == "保存" ? new[] { "second", "first" } : null, store.GetProviderOrder());
            }
            catch (Exception ex) { failure = ex; }
            finally { Application.ThreadException -= listener; File.Delete(path); }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(15)), "Settings popup lifetime check did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
