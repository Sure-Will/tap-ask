using System.Runtime.ExceptionServices;
using TapAsk;
using TapAsk.Core;
using Xunit;

namespace TapAsk.WindowsTests;

public class SettingsFormTests
{
    [Fact]
    public void SettingsCombinesGeneralShortcutAndProviderPages()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                Provider[] providers = [new("first", "First", new Uri("https://first.invalid/"), ["first.invalid"]),
                    new("second", "Second", new Uri("https://second.invalid/"), ["second.invalid"])];
                Provider[]? savedOrder = null;
                var store = new SettingsStore(Path.Combine(Path.GetTempPath(), $"tapask-settings-test-{Guid.NewGuid()}.json"));
                var updater = new AppUpdater(store);
                using var form = new SettingsForm(providers, providers.Reverse().ToArray(), GlobalShortcut.Default,
                    _ => true, order => savedOrder = order, updater, store)
                {
                    StartPosition = FormStartPosition.Manual,
                    Location = new Point(-3000, -3000)
                };
                form.Show();
                var tabs = form.Controls.OfType<TabControl>().Single();
                Assert.Equal(new[] { "通用", "快捷键", "服务商排序" }, tabs.TabPages.Cast<TabPage>().Select(page => page.Text));
                tabs.SelectedIndex = 1;
                Assert.True(form.ShortcutSelected);
                Assert.Contains(form.ShortcutForm, tabs.TabPages[1].Controls.Cast<Control>());
                tabs.SelectedIndex = 2;
                Assert.False(form.ShortcutSelected);
                var orderForm = Assert.Single(tabs.TabPages[2].Controls.OfType<ProviderOrderForm>());
                var buttons = Assert.Single(orderForm.Controls.OfType<FlowLayoutPanel>()).Controls.OfType<Button>().ToArray();
                Assert.Single(buttons, button => button.Text == "恢复默认").PerformClick();
                Assert.Single(buttons, button => button.Text == "保存").PerformClick();
                Assert.NotNull(savedOrder);
                Assert.Equal(providers, savedOrder);
                Assert.False(form.Visible);

                bool savedOnCancel = false;
                using var cancelForm = new SettingsForm(providers, providers, GlobalShortcut.Default,
                    _ => true, _ => savedOnCancel = true, updater, store)
                {
                    StartPosition = FormStartPosition.Manual,
                    Location = new Point(-3000, -3000)
                };
                cancelForm.Show();
                var cancelTabs = cancelForm.Controls.OfType<TabControl>().Single();
                cancelTabs.SelectedIndex = 2;
                var cancelOrder = Assert.Single(cancelTabs.TabPages[2].Controls.OfType<ProviderOrderForm>());
                var cancelButtons = Assert.Single(cancelOrder.Controls.OfType<FlowLayoutPanel>()).Controls.OfType<Button>();
                Assert.Single(cancelButtons, button => button.Text == "取消").PerformClick();
                Assert.False(savedOnCancel);
                Assert.False(cancelForm.Visible);
            }
            catch (Exception ex) { failure = ex; }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.True(thread.Join(TimeSpan.FromSeconds(10)), "Settings interaction did not complete.");
        if (failure is not null) ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
