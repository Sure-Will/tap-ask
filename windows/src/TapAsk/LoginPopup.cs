using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System.Diagnostics;
using TapAsk.Core;

namespace TapAsk;

internal sealed class LoginPopup : Form
{
    private readonly ProviderSession opener;
    private readonly Uri initialUrl;
    private readonly Label hostLabel = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, Padding = new Padding(10, 0, 4, 0) };
    private readonly Button complete = new() { Dock = DockStyle.Right, Width = 145, Text = "完成，回到主窗口" };
    private readonly Panel failure = new() { Dock = DockStyle.Fill, BackColor = Color.FromArgb(30, 30, 30), Visible = false };
    private readonly Label failureLabel = new() { Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, Text = "登录页打不开" };
    private readonly Button retry = new() { Text = "重试", AutoSize = true, Anchor = AnchorStyles.None };
    private readonly System.Windows.Forms.Timer loadTimer = new() { Interval = 250 };
    private readonly System.Windows.Forms.Timer noticeTimer = new() { Interval = 4500 };
    private readonly Label noticeLabel = new() { Dock = DockStyle.Top, Height = 36, TextAlign = ContentAlignment.MiddleCenter, ForeColor = Color.White, BackColor = Color.FromArgb(55, 55, 55), AutoEllipsis = true, Visible = false };
    private readonly NavigationNoticeGate noticeGate = new();
    private readonly PageLoadDeadline deadline = new();
    private ExternalLinkMenu? externalLinkMenu;
    private bool hasCommittedPage;
    private bool loading;
    private TimeSpan loadingStarted;
    private ulong activeNavigationId;
    private Rectangle? placedScreen;
    private bool userAdjusted;
    public WebView2 View { get; } = new() { Dock = DockStyle.Fill };
    public Uri InitialUrl => initialUrl;
    public event Action? Completed;

    public LoginPopup(ProviderSession opener, Uri initialUrl)
    {
        this.opener = opener;
        this.initialUrl = initialUrl;
        Text = NavigationPolicy.Origin(initialUrl);
        ClientSize = new Size(480, 640);
        MinimumSize = new Size(360, 480);
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        var toolbar = new Panel { Dock = DockStyle.Bottom, Height = 38 };
        toolbar.Controls.Add(hostLabel); toolbar.Controls.Add(complete);
        failure.Controls.Add(retry); failure.Controls.Add(failureLabel); retry.BringToFront();
        failure.Resize += (_, _) => retry.Location = new Point((failure.Width - retry.Width) / 2, failure.Height / 2 + 28);
        Controls.Add(failure); Controls.Add(View); Controls.Add(toolbar); Controls.Add(noticeLabel);
        complete.Click += (_, _) => Completed?.Invoke();
        retry.Click += (_, _) => Retry();
        hostLabel.Text = initialUrl.IdnHost;
        ResizeEnd += (_, _) => userAdjusted = true;
        loadTimer.Tick += (_, _) => UpdateLoading();
        noticeTimer.Tick += (_, _) => { noticeTimer.Stop(); noticeLabel.Visible = false; };
        loadTimer.Start();
    }

    public async Task InitializeAsync(CoreWebView2Environment environment)
    {
        await View.EnsureCoreWebView2Async(environment);
        var core = View.CoreWebView2;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        core.Settings.IsWebMessageEnabled = false;
        externalLinkMenu = new ExternalLinkMenu(core, opener.Policy, () => Visible && !IsDisposed && opener.IsActive, OpenExternal);
        View.KeyDown += (_, e) =>
        {
            if (!e.Control || e.Alt || e.Shift) return;
            var keyData = e.KeyData;
            if (e.KeyCode == Keys.R)
            {
                e.Handled = e.SuppressKeyPress = true;
                BeginInvoke(Retry);
            }
            else if (e.KeyCode is >= Keys.D1 and <= Keys.D6 or Keys.Oemcomma && Owner is MainForm main)
            {
                e.Handled = e.SuppressKeyPress = true;
                main.BeginInvoke(() => main.HandleWebShortcut(keyData));
            }
        };
        core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
        core.DownloadStarting += (_, e) =>
        {
            e.Cancel = true;
            NavigationLog.Write(opener.Provider.Id, "popup-download", ProviderSession.Parse(e.DownloadOperation.Uri), "cancel");
        };
        core.LaunchingExternalUriScheme += (_, e) => e.Cancel = true;
        core.NavigationStarting += (_, e) => CheckNavigation(e, true);
        core.FrameNavigationStarting += (_, e) => CheckNavigation(e, false);
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            var url = ProviderSession.Parse(e.Uri);
            var source = ProviderSession.Parse(e.OriginalSourceFrameInfo?.Source);
            var decision = opener.Policy.Action(url, true, e.IsUserInitiated, null, false, source);
            NavigationLog.Write(opener.Provider.Id, "popup-new-window", url,
                decision == NavigationDecision.Browser ? "cancel-unknown-method" : decision.ToString().ToLowerInvariant());
            if (decision == NavigationDecision.Allow && url is not null) core.Navigate(url.AbsoluteUri);
            else ShowBlocked(url, decision);
        };
        core.SourceChanged += (_, _) =>
        {
            var current = ProviderSession.Parse(core.Source);
            hostLabel.Text = current?.IdnHost ?? "";
            Text = NavigationPolicy.Origin(current);
        };
        core.NavigationCompleted += (_, e) =>
        {
            if (e.NavigationId != activeNavigationId) return;
            if (e.WebErrorStatus == CoreWebView2WebErrorStatus.OperationCanceled) return;
            deadline.Finish();
            loading = false;
            if (e.IsSuccess) { hasCommittedPage = true; HideOverlay(); }
            else if (!hasCommittedPage) ShowFailure();
        };
        core.ProcessFailed += (_, e) =>
        {
            if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited)
            {
                hasCommittedPage = false;
                deadline.Finish();
                loading = false;
                BeginInvoke(Retry);
            }
        };
        core.WindowCloseRequested += (_, _) => BeginInvoke(Close);
    }

    public void PlaceNear(Form parent)
    {
        var screen = Screen.FromControl(parent);
        if (userAdjusted || placedScreen == screen.Bounds) return;
        placedScreen = screen.Bounds;
        var work = screen.WorkingArea;
        float scale = parent.DeviceDpi / 96f;
        int desiredWidth = (int)Math.Round(480 * scale), desiredHeight = (int)Math.Round(640 * scale);
        var frame = PopupPlacement.Place(new PanelRect(parent.Left, parent.Top, parent.Width, parent.Height),
            new PanelRect(work.Left, work.Top, work.Width, work.Height), desiredWidth, desiredHeight, (int)Math.Round(12 * scale));
        MinimumSize = new Size(Math.Min((int)Math.Round(360 * scale), frame.Width), Math.Min((int)Math.Round(480 * scale), frame.Height));
        Bounds = new Rectangle(frame.X, frame.Y, frame.Width, frame.Height);
    }

    private void Retry()
    {
        if (!opener.Policy.IsPanelUrl(initialUrl)) return;
        HideOverlay();
        // Initial URL is an allowed HTTPS URL; navigate performs a fresh GET.
        View.CoreWebView2.Navigate(initialUrl.AbsoluteUri);
    }

    private void CheckNavigation(CoreWebView2NavigationStartingEventArgs e, bool topLevel)
    {
        var url = ProviderSession.Parse(e.Uri);
        var source = ProviderSession.Parse(View.CoreWebView2.Source);
        var decision = opener.Policy.Action(url, topLevel, e.IsUserInitiated && !e.IsRedirected, null, false, source);
        if (decision != NavigationDecision.Allow)
        {
            e.Cancel = true;
            if (topLevel) ShowBlocked(url, decision);
        }
        else if (topLevel)
        {
            activeNavigationId = e.NavigationId;
            if (!hasCommittedPage)
            {
                var now = Stopwatch.GetElapsedTime(0);
                deadline.Start(now);
                if (!loading) loadingStarted = now;
                loading = true;
            }
        }
        NavigationLog.Write(opener.Provider.Id, topLevel ? "popup-action" : "popup-frame-action", url,
            decision == NavigationDecision.Browser ? "cancel-unknown-method" : decision.ToString().ToLowerInvariant());
    }

    private void UpdateLoading()
    {
        if (!loading || View.CoreWebView2 is null) return;
        var now = Stopwatch.GetElapsedTime(0);
        if (deadline.HasExpired(now))
        {
            deadline.Finish();
            loading = false;
            try { View.CoreWebView2.Stop(); }
            catch (System.Runtime.InteropServices.COMException)
            { NavigationLog.Write(opener.Provider.Id, "popup-stop", null, "failed"); }
            ShowFailure();
        }
        else if (now - loadingStarted >= TimeSpan.FromMilliseconds(400))
        {
            failureLabel.Text = "正在打开登录页…";
            retry.Visible = false;
            View.Visible = false;
            failure.Visible = true;
            failure.BringToFront();
        }
    }

    private void ShowFailure()
    {
        failureLabel.Text = "登录页打不开";
        retry.Visible = true;
        View.Visible = false;
        failure.Visible = true;
        failure.BringToFront();
    }

    private void HideOverlay()
    {
        failure.Visible = false;
        View.Visible = true;
    }

    private void ShowBlocked(Uri? url, NavigationDecision decision)
    {
        if (url is null || string.IsNullOrEmpty(url.IdnHost) ||
            !noticeGate.ShouldShow("blocked", url.IdnHost, Stopwatch.GetElapsedTime(0))) return;
        noticeLabel.Text = decision == NavigationDecision.Browser
            ? $"已拦截 {url.IdnHost}；可右键链接交给浏览器"
            : $"已拦截 {url.IdnHost}：TapAsk 只打开 {opener.Provider.Name} 和常见登录页";
        noticeLabel.Visible = true;
        noticeTimer.Stop(); noticeTimer.Start();
    }

    private void OpenExternal(Uri url)
    {
        bool opened = ExternalBrowser.Open(url);
        NavigationLog.Write(opener.Provider.Id, "popup-browser-open", url, opened ? "opened" : "failed");
        if (!noticeGate.ShouldShow(opened ? "browser" : "browser-failed", url.IdnHost, Stopwatch.GetElapsedTime(0))) return;
        noticeLabel.Text = opened ? $"已在浏览器中打开 {url.IdnHost}" : $"无法打开浏览器：{url.IdnHost}";
        noticeLabel.Visible = true;
        noticeTimer.Stop(); noticeTimer.Start();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { externalLinkMenu?.Dispose(); loadTimer.Dispose(); noticeTimer.Dispose(); }
        base.Dispose(disposing);
    }
}
