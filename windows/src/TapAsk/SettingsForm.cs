using TapAsk.Core;

namespace TapAsk;

internal sealed class SettingsForm : Form
{
    private readonly TabControl tabs = new() { Dock = DockStyle.Fill };
    private readonly CheckBox startup = new() { Text = "登录时启动 TapAsk", AutoSize = true };
    private readonly CheckBox automatic = new() { Text = "自动检查并下载更新", AutoSize = true };
    private readonly Label updateStatus = new() { AutoSize = true };
    private readonly AppUpdater updater;
    private bool updatingStartup;
    public ShortcutSettingsForm ShortcutForm { get; }
    public bool ShortcutSelected => tabs.SelectedIndex == 1;

    public SettingsForm(Provider[] defaults, Provider[] ordered, GlobalShortcut shortcut,
                        Func<GlobalShortcut, bool> saveShortcut, Action<Provider[]> saveOrder,
                        AppUpdater updater, SettingsStore settings)
    {
        this.updater = updater;
        Text = "设置";
        ClientSize = new Size(430, 400);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MinimizeBox = MaximizeBox = false;
        ShowInTaskbar = false;
        TopMost = true;
        var general = new TabPage("通用") { Padding = new Padding(20) };
        var layout = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new Padding(4) };
        startup.Checked = StartupRegistration.IsEnabled();
        automatic.Checked = updater.Enabled;
        startup.CheckedChanged += (_, _) =>
        {
            if (updatingStartup) return;
            try { StartupRegistration.SetEnabled(startup.Checked); settings.SaveAutoStartAttempted(); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException or InvalidOperationException)
            {
                MessageBox.Show(this, ex.Message, "无法更改登录时启动", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                updatingStartup = true;
                startup.Checked = StartupRegistration.IsEnabled();
                updatingStartup = false;
            }
        };
        automatic.CheckedChanged += (_, _) => updater.SetEnabled(automatic.Checked);
        var check = new Button { Text = "检查更新…", AutoSize = true };
        check.Click += async (_, _) => { await updater.CheckAsync(interactive: true); updateStatus.Text = updater.Status; };
        var version = new Label { AutoSize = true, Text = $"TapAsk {Application.ProductVersion}", Margin = new Padding(3, 24, 3, 3) };
        layout.Controls.AddRange([startup, automatic, check, updateStatus, version]);
        general.Controls.Add(layout);
        tabs.TabPages.Add(general);

        ShortcutForm = new ShortcutSettingsForm(shortcut, saveShortcut);
        var shortcutTab = new TabPage("快捷键");
        Embed(ShortcutForm, shortcutTab);
        ShortcutForm.FormClosed += (_, _) => { if (!IsDisposed && !Disposing) Close(); };
        tabs.TabPages.Add(shortcutTab);

        var orderForm = new ProviderOrderForm(defaults, ordered);
        var orderTab = new TabPage("服务商排序");
        Embed(orderForm, orderTab);
        orderForm.FormClosed += (_, _) =>
        {
            if (orderForm.DialogResult == DialogResult.OK) saveOrder(orderForm.OrderedProviders);
            if (!IsDisposed && !Disposing) Close();
        };
        tabs.TabPages.Add(orderTab);
        Controls.Add(tabs);
        updateStatus.Text = updater.Status;
    }

    private static void Embed(Form form, TabPage tab)
    {
        form.TopMost = false;
        form.TopLevel = false;
        form.FormBorderStyle = FormBorderStyle.None;
        form.Dock = DockStyle.Fill;
        tab.Controls.Add(form);
        form.Show();
    }
}
