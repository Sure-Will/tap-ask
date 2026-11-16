using System.Runtime.ExceptionServices;
using System.Reflection;
using TapAsk;
using TapAsk.Core;
using Xunit;

namespace TapAsk.WindowsTests;

public class SettingsFormTests
{
    [Fact]
    public void TrayIconDoesNotUseAWinFormsContextMenu()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string path = Path.Combine(Path.GetTempPath(), $"tapask-tray-test-{Guid.NewGuid()}.json");
            try
            {
                Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"])];
                using var owner = new MainForm(settingsStore: new SettingsStore(path), providerCatalog: new([], providers));
                var tray = Assert.IsType<NotifyIcon>(typeof(MainForm).GetField("tray", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(owner));
                Assert.Null(tray.ContextMenuStrip);
            }
            catch (Exception ex) { failure = ex; }
            finally { File.Delete(path); }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Tray menu check did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }

    [Fact]
    public void TrayMenuExposesSettingsWithoutASeparateSettingsWindow()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            string path = Path.Combine(Path.GetTempPath(), $"tapask-tray-test-{Guid.NewGuid()}.json");
            try
            {
                Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"]),
                    new("second", "Second", new Uri("https://second.invalid/"), ["second.invalid"])];
                var store = new SettingsStore(path);
                using var owner = new MainForm(settingsStore: store, providerCatalog: new([], providers));
                var items = owner.BuildMenu();
                var titles = items.Select(item => item.Title).ToArray();
                Assert.DoesNotContain("设置…", titles);
                Assert.Contains("登录时启动 TapAsk", titles);
                Assert.Contains("自动检查并下载更新", titles);
                Assert.Contains("设置快捷键…", titles);
                Assert.Contains("调整服务商顺序…", titles);
                Assert.Contains("检查更新…", titles);
                var first = Assert.Single(items, item => item.Title == "First");
                var second = Assert.Single(items, item => item.Title == "Second");
                Assert.True(first.Checked);
                Assert.False(second.Checked);
                Assert.Equal("Ctrl+1", first.Shortcut);
                Assert.Equal("Ctrl+2", second.Shortcut);
                var automatic = Assert.Single(items, item => item.Title == "自动检查并下载更新");
                Assert.True(automatic.Checked);
                automatic.OnClick!();
                Assert.False(store.AutoUpdateEnabled);
                Assert.False(Assert.Single(owner.BuildMenu(), item => item.Title == "自动检查并下载更新").Checked);
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
        var items = new List<TrayMenuItem>();
        int installs = 0;
        MainForm.AddUpdateMenuItems(items, false, () => installs++);
        Assert.Empty(items);
        MainForm.AddUpdateMenuItems(items, true, () => installs++);
        Assert.Equal(new[] { "更新已下载", "立即安装并重启" }, items.Select(i => i.Title));
        Assert.False(items[0].Enabled);
        items[1].OnClick!();
        Assert.Equal(1, installs);
    }

}
