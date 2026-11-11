using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using TapAsk.Core;

namespace TapAsk;

internal sealed class MainForm : Form
{
    private const int WmHotkey = 0x0312, WsExToolWindow = 0x80;
    private const int WmNcCalcSize = 0x0083, WmNcHitTest = 0x0084;
    private readonly NotifyIcon tray;
    private Icon trayIcon;
    private readonly ContextMenuStrip menu = new();
    private readonly Panel pageHost = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(30, 30, 30) };
    private readonly Panel loadOverlay = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(30, 30, 30), Visible = false };
    private readonly Label loadMessage = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White };
    private readonly Button retryButton = new() { Text = "重试", AutoSize = true, Anchor = AnchorStyles.None, Visible = false };
    private readonly System.Windows.Forms.Timer maintenanceTimer = new() { Interval = 250 };
    private readonly System.Windows.Forms.Timer noticeTimer = new() { Interval = 4500 };
    private readonly System.Windows.Forms.Timer updateTimer = new() { Interval = 60 * 60 * 1000 };
    private readonly Label noticeLabel = new() { Dock = DockStyle.Top, Height = 36, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, BackColor = Color.FromArgb(55, 55, 55), AutoEllipsis = true, Visible = false };
    private readonly Label originLabel = new() { Dock = DockStyle.Top, Height = 28, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, BackColor = Color.FromArgb(45, 45, 45), AutoEllipsis = true, Visible = false };
    private readonly NavigationNoticeGate noticeGate = new();
    private readonly ProviderCatalog catalog;
    private readonly SettingsStore settings = new();
    private readonly AppUpdater updater;
    private readonly Dictionary<string, ProviderSession> sessions = new(StringComparer.Ordinal);
    private readonly SessionRetentionPolicy retention = new();
    private Provider[] providers;
    private Provider provider;
    private CoreWebView2Environment? environment;
    private LoginPopup? loginPopup;
    private Uri? interruptedLoginUrl;
    private ShortcutSettingsForm? shortcutSettings;
    private GlobalShortcut shortcut;
    private int hotkeyId = 1;
    private DragHandleForm? dragHandle;
    private ResizeBorderForm? resizeBorder;
    private bool hotkeyRegistered, quitting;
    private bool suppressInitialShow;
    private bool suppressPopupFocus;
    private bool environmentStarted;
    private IntPtr previousForeground;

    public MainForm(bool startHidden = false)
    {
        suppressInitialShow = startHidden;
        updater = new AppUpdater(settings);
        Text = "TapAsk";
        ClientSize = new Size(480, 720);
        MinimumSize = new Size(360, 480);
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;
        TopMost = true;
        catalog = ProviderCatalog.Load(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));
        providers = ProviderOrder.Ordered(catalog.Providers, settings.GetProviderOrder());
        shortcut = settings.GetGlobalShortcut();
        provider = ProviderSelection.Restored(providers, settings.GetLastProviderId())
            ?? throw new InvalidDataException("服务商目录必须至少包含一个服务商。");
        settings.SaveLastProviderId(provider.Id);
        retention.DidDisplay(provider.Id, Now());
        Controls.Add(pageHost);
        Controls.Add(originLabel);
        Controls.Add(noticeLabel);
        noticeTimer.Tick += (_, _) => { noticeTimer.Stop(); noticeLabel.Visible = false; };
        loadOverlay.Controls.Add(retryButton);
        loadOverlay.Controls.Add(loadMessage);
        retryButton.BringToFront();
        pageHost.Controls.Add(loadOverlay);
        loadOverlay.Resize += (_, _) => retryButton.Location = new Point((loadOverlay.Width - retryButton.Width) / 2, loadOverlay.Height / 2 + 32);
        retryButton.Click += (_, _) => ActiveSession?.Reload();
        menu.Opening += (_, _) => BuildMenu();
        trayIcon = StatusIcon.Create();
        tray = new NotifyIcon { Icon = trayIcon, Text = "TapAsk — 单击呼出，右键菜单", ContextMenuStrip = menu, Visible = true };
        SystemEvents.UserPreferenceChanged += OnUserPreferenceChanged;
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) TogglePanel(); };
        Shown += (_, _) => PlaceOnCursorScreen();
        Shown += (_, _) =>
        {
            resizeBorder = new ResizeBorderForm(this); resizeBorder.Show(this); resizeBorder.UpdatePosition();
            dragHandle = new DragHandleForm(this); dragHandle.Show(this); dragHandle.UpdatePosition();
        };
        Move += (_, _) => UpdateOverlays();
        Resize += (_, _) => UpdateOverlays();
        DpiChanged += (_, _) => UpdateOverlays();
        VisibleChanged += (_, _) =>
        {
            if (dragHandle is null) return;
            if (Visible) { resizeBorder?.Show(this); dragHandle.Show(this); UpdateOverlays(); }
            else { resizeBorder?.Hide(); dragHandle.Hide(); }
        };
        ResizeEnd += (_, _) => SaveFrame();
        maintenanceTimer.Tick += (_, _) =>
        {
            var now = Now();
            ReleaseSession(retention.Expire(now));
            foreach (var retainedSession in sessions.Values.ToArray()) retainedSession.CheckTimeout(now);
            if (ActiveSession is { } session) SessionChanged(session);
        };
        maintenanceTimer.Start();
        updateTimer.Tick += async (_, _) => await updater.CheckIfDueAsync();
        updateTimer.Start();
    }

    private ProviderSession? ActiveSession => sessions.GetValueOrDefault(provider.Id);
    internal bool IsActiveSession(ProviderSession session) => Visible && !IsDisposed && ActiveSession == session;
    private static TimeSpan Now() => Stopwatch.GetElapsedTime(0);

    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= WsExToolWindow; return value; }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        int roundCorners = 2;
        DwmSetWindowAttribute(Handle, 33, ref roundCorners, sizeof(int));
        hotkeyRegistered = RegisterHotKey(Handle, hotkeyId, (uint)shortcut.Modifiers | 0x4000, shortcut.Key);
        NavigationLog.Write(provider.Id, "hotkey-register", null, hotkeyRegistered ? "registered" : "failed");
        if (!hotkeyRegistered)
            BeginInvoke(() => MessageBox.Show(this, $"无法注册 {shortcut}。请检查其他程序是否占用了该快捷键；仍可使用托盘图标。", "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Warning));
        if (!environmentStarted)
        {
            environmentStarted = true;
            BeginInvoke(async () => { await InitializeEnvironmentAsync(); await updater.CheckIfDueAsync(); });
        }
    }

    protected override void SetVisibleCore(bool value)
    {
        if (value && suppressInitialShow)
        {
            suppressInitialShow = false;
            if (!IsHandleCreated) CreateHandle();
            base.SetVisibleCore(false);
            return;
        }
        base.SetVisibleCore(value);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        if (hotkeyRegistered) UnregisterHotKey(Handle, hotkeyId);
        hotkeyRegistered = false;
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmNcCalcSize && message.WParam != IntPtr.Zero) { message.Result = IntPtr.Zero; return; }
        if (message.Msg == WmNcHitTest)
        {
            base.WndProc(ref message);
            if (message.Result.ToInt32() == (int)FrameHit.Client)
            {
                long coordinates = message.LParam.ToInt64();
                var point = PointToClient(new Point(unchecked((short)coordinates), unchecked((short)(coordinates >> 16))));
                int border = Math.Max(1, (int)Math.Round(6 * DeviceDpi / 96.0));
                message.Result = new IntPtr((int)WindowFrameHitTest.At(ClientSize.Width, ClientSize.Height, point.X, point.Y, border));
            }
            return;
        }
        if (message.Msg == WmHotkey && message.WParam.ToInt32() == hotkeyId)
        {
            if (shortcutSettings is not null) { shortcutSettings.RecordShortcut(shortcut); return; }
            NavigationLog.Write(provider.Id, "hotkey", null, Visible ? "hide" : "show");
            TogglePanel(); return;
        }
        if ((uint)message.Msg == Program.ShowExistingMessage) { ShowPanel(); return; }
        base.WndProc(ref message);
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData) => HandleWebShortcut(keyData) || base.ProcessCmdKey(ref msg, keyData);

    internal bool HandleWebShortcut(Keys keyData)
    {
        if ((keyData & Keys.Modifiers) != Keys.Control) return false;
        var key = keyData & Keys.KeyCode;
        if (key >= Keys.D1 && key <= Keys.D6)
        {
            var index = (int)key - (int)Keys.D1;
            if (index < providers.Length) SwitchProvider(providers[index]);
            return true;
        }
        if (key == Keys.R) { ActiveSession?.Reload(); return true; }
        if (key == Keys.Oemcomma) { EditShortcut(); return true; }
        return false;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!quitting && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; HidePanel(); }
        else
        {
            ActiveSession?.SaveCurrentPage();
            SaveFrame();
            try { updater.PrepareNormalExit(); }
            catch (Exception ex) when (ex is IOException or InvalidOperationException or COMException)
            { NavigationLog.Write("app", "update-apply", null, ex.GetType().Name); }
        }
        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            SystemEvents.UserPreferenceChanged -= OnUserPreferenceChanged;
            maintenanceTimer.Dispose();
            noticeTimer.Dispose();
            updateTimer.Dispose();
            loginPopup?.Dispose();
            foreach (var session in sessions.Values) session.Dispose();
            sessions.Clear();
            resizeBorder?.Dispose(); dragHandle?.Dispose();
            tray.Visible = false; menu.Dispose(); tray.Dispose(); trayIcon.Dispose();
        }
        base.Dispose(disposing);
    }

    private void OnUserPreferenceChanged(object sender, UserPreferenceChangedEventArgs e)
    {
        if (!IsHandleCreated || IsDisposed || Disposing) return;
        try { BeginInvoke(() =>
        {
            if (IsDisposed || Disposing) return;
            var previous = trayIcon;
            trayIcon = StatusIcon.Create();
            tray.Icon = trayIcon;
            previous.Dispose();
        }); }
        catch (InvalidOperationException) { /* The window closed before the notification was delivered. */ }
    }

    private void BuildMenu()
    {
        menu.Items.Clear();
        menu.Items.Add(new ToolStripMenuItem(Visible ? "隐藏 TapAsk" : "显示 TapAsk", null, (_, _) => TogglePanel()) { ShortcutKeyDisplayString = shortcut.ToString() });
        menu.Items.Add(new ToolStripSeparator());
        for (int i = 0; i < providers.Length; i++)
        {
            var itemProvider = providers[i];
            menu.Items.Add(new ToolStripMenuItem(itemProvider.Name, null, (_, _) => SwitchProvider(itemProvider))
            { Checked = itemProvider.Id == provider.Id, ShortcutKeyDisplayString = $"Ctrl+{i + 1}" });
        }
        menu.Items.Add(new ToolStripMenuItem("服务商排序…", null, (_, _) => EditProviderOrder()));
        menu.Items.Add(new ToolStripMenuItem("快捷键设置…", null, (_, _) => EditShortcut()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("重新加载", null, (_, _) => ActiveSession?.Reload()) { ShortcutKeyDisplayString = "Ctrl+R" });
        menu.Items.Add(new ToolStripMenuItem("释放其他服务商页面", null, (_, _) => ReleaseSession(retention.ReleaseBackground()))
        { Enabled = sessions.Keys.Any(id => id != provider.Id) });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("检查更新…", null, async (_, _) => await updater.CheckAsync(interactive: true)));
        menu.Items.Add(new ToolStripMenuItem("自动更新", null, (_, _) => updater.SetEnabled(!updater.Enabled)) { Checked = updater.Enabled });
        if (!string.IsNullOrEmpty(updater.Status)) menu.Items.Add(new ToolStripMenuItem(updater.Status) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("退出 TapAsk", null, (_, _) => ExitApp()));
    }

    private void EditProviderOrder()
    {
        using var form = new ProviderOrderForm(catalog.Providers, providers);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        providers = form.OrderedProviders;
        settings.SaveProviderOrder(providers.Select(p => p.Id));
    }

    private void EditShortcut()
    {
        using var form = new ShortcutSettingsForm(shortcut, SaveShortcut);
        shortcutSettings = form;
        try { form.ShowDialog(this); }
        finally { shortcutSettings = null; }
    }

    private bool SaveShortcut(GlobalShortcut next)
    {
        if (next == shortcut && hotkeyRegistered) return true;
        int nextId = hotkeyId == 1 ? 2 : 1;
        if (!RegisterHotKey(Handle, nextId, (uint)next.Modifiers | 0x4000, next.Key))
        {
            MessageBox.Show(shortcutSettings, "这组快捷键已被占用，原快捷键保持不变。", "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        if (hotkeyRegistered) UnregisterHotKey(Handle, hotkeyId);
        hotkeyId = nextId;
        hotkeyRegistered = true;
        shortcut = next;
        settings.SaveGlobalShortcut(next);
        return true;
    }

    private void SwitchProvider(Provider next)
    {
        if (provider.Id == next.Id)
        {
            if (!Visible) ShowPanel();
            else if (ActiveSession is { } current) RecoverSession(current);
            return;
        }
        interruptedLoginUrl = null;
        noticeTimer.Stop();
        noticeLabel.Visible = false;
        suppressPopupFocus = true;
        try { loginPopup?.Close(); }
        finally { suppressPopupFocus = false; }
        ActiveSession?.SaveCurrentPage();
        if (ActiveSession is { } old) old.View.Visible = false;
        ReleaseSession(retention.Expire(Now()));
        provider = next;
        settings.SaveLastProviderId(provider.Id);
        ReleaseSession(retention.DidDisplay(provider.Id, Now()));
        EnsureSession();
        if (ActiveSession is { } active) RecoverSession(active);
        if (ActiveSession is { } session) SessionChanged(session);
        if (Visible) ActiveSession?.View.Focus(); else ShowPanel();
    }

    private void ReleaseSession(string? id)
    {
        if (id is null || !sessions.Remove(id, out var session)) return;
        pageHost.Controls.Remove(session.View);
        session.Dispose();
    }

    private void EnsureSession()
    {
        if (environment is null || sessions.ContainsKey(provider.Id)) return;
        var session = new ProviderSession(this, provider, catalog.IdentityHosts, settings, environment);
        sessions.Add(provider.Id, session);
        pageHost.Controls.Add(session.View);
        _ = session.InitializeAsync();
    }

    internal void SessionChanged(ProviderSession session)
    {
        if (IsDisposed || session.Provider.Id != provider.Id) return;
        if (session.NeedsRecreate)
        {
            loadMessage.Text = "正在恢复网页…";
            retryButton.Visible = false;
            session.View.Visible = false;
            loadOverlay.Visible = true;
            loadOverlay.BringToFront();
            return;
        }
        var current = session.CurrentUrl;
        originLabel.Visible = current is not null && session.Policy.IsPanelUrl(current) && !session.Policy.IsProviderUrl(current);
        originLabel.Text = originLabel.Visible ? NavigationPolicy.Origin(current) : "";
        bool waiting = session.Initializing || (session.Loading && DateTimeOffset.UtcNow - session.LoadingStarted >= TimeSpan.FromMilliseconds(400));
        bool failed = session.Failure is not null;
        loadMessage.Text = failed ? session.Failure : "正在打开…";
        retryButton.Visible = failed && !session.Initializing;
        loadOverlay.Visible = waiting || failed;
        session.View.Visible = !loadOverlay.Visible;
        if (loadOverlay.Visible) loadOverlay.BringToFront();
        else session.View.BringToFront();
    }

    internal void SessionProcessFailed(ProviderSession session)
    {
        if (!sessions.TryGetValue(session.Provider.Id, out var retained) || retained != session) return;
        // The environment event coordinates recovery of all WebViews after a browser-process crash.
        if (session.NeedsRecreate) { SessionChanged(session); return; }
        if (Visible && session.Provider.Id == provider.Id) RecoverSession(session);
        if (ActiveSession is { } active) SessionChanged(active);
    }

    private void RecoverSession(ProviderSession session)
    {
        if (!session.NeedsRecreate) session.PrepareForDisplay();
    }

    internal void NavigationBlocked(ProviderSession session, Uri? url, NavigationDecision decision)
    {
        if (session.Provider.Id != provider.Id || url is null || string.IsNullOrEmpty(url.IdnHost) ||
            !noticeGate.ShouldShow("blocked", url.IdnHost, Now())) return;
        noticeLabel.Text = decision == NavigationDecision.Browser
            ? $"已拦截 {url.IdnHost}；可右键链接交给浏览器"
            : $"已拦截 {url.IdnHost}：TapAsk 只打开 {provider.Name} 和常见登录页";
        noticeLabel.Visible = true;
        noticeTimer.Stop(); noticeTimer.Start();
    }

    internal void OpenExternal(ProviderSession session, Uri url)
    {
        if (!IsActiveSession(session)) return;
        bool opened = ExternalBrowser.Open(url);
        NavigationLog.Write(session.Provider.Id, "browser-open", url, opened ? "opened" : "failed");
        if (!noticeGate.ShouldShow(opened ? "browser" : "browser-failed", url.IdnHost, Now())) return;
        noticeLabel.Text = opened ? $"已在浏览器中打开 {url.IdnHost}" : $"无法打开浏览器：{url.IdnHost}";
        noticeLabel.Visible = true;
        noticeTimer.Stop(); noticeTimer.Start();
    }

    internal async void HandleNewWindow(ProviderSession session, CoreWebView2NewWindowRequestedEventArgs e)
    {
        if (!Visible || session.Provider.Id != provider.Id) { e.Handled = true; return; }
        var url = ProviderSession.Parse(e.Uri);
        var source = ProviderSession.Parse(e.OriginalSourceFrameInfo?.Source);
        var decision = session.Policy.Action(url, true, e.IsUserInitiated, null, false, source);
        NavigationLog.Write(session.Provider.Id, "main-new-window", url,
            decision == NavigationDecision.Browser ? "cancel-unknown-method" : decision.ToString().ToLowerInvariant());
        if (decision != NavigationDecision.Allow || url is null)
        {
            e.Handled = true;
            NavigationBlocked(session, url, decision);
            return;
        }
        if (session.Policy.IsProviderUrl(url))
        {
            e.Handled = true;
            session.Navigate(url);
            return;
        }

        using var deferral = e.GetDeferral();
        loginPopup?.Close();
        var popup = CreateLoginPopup(session, url);
        try
        {
            popup.PlaceNear(this);
            popup.Show(this);
            await popup.InitializeAsync(environment!);
            if (IsDisposed || popup.IsDisposed || loginPopup != popup || provider.Id != session.Provider.Id)
            {
                e.Handled = true;
                return;
            }
            e.NewWindow = popup.View.CoreWebView2;
            if (Visible) { popup.Activate(); popup.View.Focus(); }
            else popup.Hide();
        }
        catch (Exception ex) when (ex is InvalidOperationException or COMException or ObjectDisposedException)
        {
            e.Handled = true;
            if (!popup.IsDisposed) popup.Close();
            NavigationLog.Write(session.Provider.Id, "popup-create", url, ex.GetType().Name);
        }
    }

    private LoginPopup CreateLoginPopup(ProviderSession session, Uri url)
    {
        var popup = new LoginPopup(session, url);
        loginPopup = popup;
        popup.FormClosed += (_, _) =>
        {
            if (loginPopup == popup) loginPopup = null;
            if (!suppressPopupFocus && Visible && !IsDisposed) { Activate(); ActiveSession?.View.Focus(); }
        };
        popup.Completed += () =>
        {
            popup.Close();
            if (provider.Id == session.Provider.Id) session.Reload();
        };
        return popup;
    }

    private async Task RestoreInterruptedLoginAsync(ProviderSession session, Uri url)
    {
        var popup = CreateLoginPopup(session, url);
        try
        {
            popup.PlaceNear(this);
            popup.Show(this);
            await popup.InitializeAsync(environment!);
            if (IsDisposed || popup.IsDisposed || loginPopup != popup || provider.Id != session.Provider.Id)
                return;
            popup.View.CoreWebView2.Navigate(url.AbsoluteUri);
            if (Visible) { popup.Activate(); popup.View.Focus(); }
            else popup.Hide();
        }
        catch (Exception ex) when (ex is InvalidOperationException or COMException or ObjectDisposedException)
        {
            if (!popup.IsDisposed) popup.Close();
            NavigationLog.Write(session.Provider.Id, "popup-recover", url, ex.GetType().Name);
        }
    }

    private async Task InitializeEnvironmentAsync()
    {
        try
        {
            var userData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TapAsk", "WebView2");
            environment = await CoreWebView2Environment.CreateAsync(userDataFolder: userData);
            environment.BrowserProcessExited += (_, e) =>
            {
                if (e.BrowserProcessExitKind == CoreWebView2BrowserProcessExitKind.Failed)
                    BeginInvoke(HandleBrowserProcessExited);
            };
            EnsureSession();
        }
        catch (WebView2RuntimeNotFoundException)
        {
            if (MessageBox.Show(this, "需要安装 Microsoft Edge WebView2 Runtime。现在打开微软下载页面吗？", "TapAsk", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
                Process.Start(new ProcessStartInfo("https://developer.microsoft.com/microsoft-edge/webview2/") { UseShellExecute = true });
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or COMException or InvalidOperationException)
        {
            MessageBox.Show(this, $"无法启动网页：{ex.GetType().Name}", "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void HandleBrowserProcessExited()
    {
        if (IsDisposed || quitting) return;
        interruptedLoginUrl = loginPopup?.InitialUrl;
        suppressPopupFocus = true;
        try { loginPopup?.Close(); }
        finally { suppressPopupFocus = false; }
        foreach (var session in sessions.Values) session.InvalidateAfterBrowserExit();
        foreach (var id in sessions.Keys.ToArray()) ReleaseSession(id);
        retention.ReleaseBackground();
        NavigationLog.Write(provider.Id, "browser-process", null, "exited");
        if (Visible) RestoreAfterBrowserExit();
    }

    private void RestoreAfterBrowserExit()
    {
        EnsureSession();
        if (interruptedLoginUrl is { } url && ActiveSession is { } session)
        {
            interruptedLoginUrl = null;
            if (session.Policy.IsPanelUrl(url)) _ = RestoreInterruptedLoginAsync(session, url);
        }
    }

    private void TogglePanel() { if (Visible) HidePanel(); else ShowPanel(); }
    private void UpdateOverlays() { resizeBorder?.UpdatePosition(); dragHandle?.UpdatePosition(); }
    private void ShowPanel()
    {
        var foreground = GetForegroundWindow();
        if (foreground != Handle) previousForeground = foreground;
        try { VirtualDesktop.MoveToForegroundDesktop(Handle, foreground); }
        catch (COMException) { NavigationLog.Write(provider.Id, "virtual-desktop", null, "move-failed"); }
        PlaceOnCursorScreen();
        Show(); WindowState = FormWindowState.Normal; Activate();
        if (ActiveSession is null) RestoreAfterBrowserExit();
        if (ActiveSession is { } active) RecoverSession(active);
        if (loginPopup is { IsDisposed: false } popup) { popup.PlaceNear(this); popup.Show(this); popup.Activate(); popup.View.Focus(); }
        else ActiveSession?.View.Focus();
    }
    private void HidePanel()
    {
        ActiveSession?.SaveCurrentPage();
        SaveFrame();
        var wasForeground = GetForegroundWindow() == Handle || (loginPopup is not null && GetForegroundWindow() == loginPopup.Handle);
        loginPopup?.Hide();
        Hide();
        if (wasForeground && previousForeground != IntPtr.Zero && IsWindow(previousForeground)) SetForegroundWindow(previousForeground);
    }
    private void ExitApp() { quitting = true; Close(); }

    private void PlaceOnCursorScreen()
    {
        var screen = Screen.FromPoint(Cursor.Position);
        var preferred = settings.GetPanelFrame() ?? ToPanelRect(Bounds);
        var work = ToPanelRect(screen.WorkingArea);
        MinimumSize = new Size(Math.Min((int)Math.Round(360 * DeviceDpi / 96.0), work.Width),
            Math.Min((int)Math.Round(480 * DeviceDpi / 96.0), work.Height));
        var result = PanelPlacement.Place(preferred, ToPanelRect(screen.Bounds), work,
            Math.Min(MinimumSize.Width, work.Width), Math.Min(MinimumSize.Height, work.Height));
        Bounds = new Rectangle(result.X, result.Y, result.Width, result.Height);
    }

    private void SaveFrame()
    {
        if (Visible && WindowState == FormWindowState.Normal) settings.SavePanelFrame(ToPanelRect(Bounds));
    }

    private static PanelRect ToPanelRect(Rectangle rectangle) => new(rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height);

    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr window);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
}
