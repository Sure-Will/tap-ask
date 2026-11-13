using System.Runtime.ExceptionServices;
using TapAsk;
using TapAsk.Core;
using Xunit;

namespace TapAsk.WindowsTests;

public class SettingsFormTests
{
    [Fact]
    public void TrayMenuExposesSettingsWithoutASeparateSettingsWindow()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string path = Path.Combine(Path.GetTempPath(), $"tapask-tray-test-{Guid.NewGuid()}.json");
            try
            {
                Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"])];
                var store = new SettingsStore(path);
                using var owner = new MainForm(settingsStore: store, providerCatalog: new([], providers));
                owner.BuildMenu();
                var titles = owner.TrayMenu.Items.Cast<ToolStripItem>().Select(item => item.Text).ToArray();
                Assert.DoesNotContain("设置…", titles);
                Assert.Contains("登录时启动 TapAsk", titles);
                Assert.Contains("自动检查并下载更新", titles);
                Assert.Contains("设置快捷键…", titles);
                Assert.Contains("调整服务商顺序…", titles);
                Assert.Contains("检查更新…", titles);
                var automatic = Assert.Single(owner.TrayMenu.Items.OfType<ToolStripMenuItem>(),
                    item => item.Text == "自动检查并下载更新");
                Assert.True(automatic.Checked);
                automatic.PerformClick();
                Assert.False(store.AutoUpdateEnabled);
            }
            catch (Exception ex) { failure = ex; }
            finally { File.Delete(path); }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Tray settings interaction did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [Fact]
    public void ReadyUpdateCanBeInstalledDirectlyFromMenu()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                using var menu = new ContextMenuStrip();
                int installs = 0;
                MainForm.AddUpdateMenuItems(menu.Items, false, () => installs++);
                Assert.Empty(menu.Items.Cast<ToolStripItem>());
                MainForm.AddUpdateMenuItems(menu.Items, true, () => installs++);
                Assert.Equal(new[] { "更新已下载", "立即安装并重启" }, menu.Items.Cast<ToolStripItem>().Select(i => i.Text));
                Assert.False(menu.Items[0].Enabled);
                ((ToolStripMenuItem)menu.Items[1]).PerformClick();
                Assert.Equal(1, installs);
            }
            catch (Exception ex) { failure = ex; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Update menu interaction did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

}
