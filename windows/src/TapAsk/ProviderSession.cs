using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using System.Diagnostics;
using TapAsk.Core;

namespace TapAsk;

// Each retained session owns its navigation state; all sessions share one persistent environment.
internal sealed class ProviderSession : IDisposable
{
    private readonly MainForm owner;
    private readonly SettingsStore settings;
    private readonly CoreWebView2Environment environment;
    private bool disposed;
    private bool restoringPage;
    private bool hasCommittedPage;
    private bool navigationInProgress;
    private ulong activeNavigationId;
    private readonly PageLoadDeadline deadline = new();
    private ExternalLinkMenu? externalLinkMenu;

    public Provider Provider { get; }
    public NavigationPolicy Policy { get; }
    public WebView2 View { get; }
    public bool Initializing { get; private set; } = true;
    public bool Loading { get; private set; }
    public DateTimeOffset LoadingStarted { get; private set; }
    public string? Failure { get; private set; }
    public bool NeedsReload { get; private set; }
    public bool NeedsRecreate { get; private set; }
    public bool HasPage => hasCommittedPage;
    public Uri? CurrentUrl { get; private set; }
    internal bool IsActive => owner.IsActiveSession(this);

    public ProviderSession(MainForm owner, Provider provider, IEnumerable<string> identities,
                           SettingsStore settings, CoreWebView2Environment environment)
    {
        this.owner = owner;
        this.settings = settings;
        this.environment = environment;
        Provider = provider;
        Policy = new NavigationPolicy(provider, identities);
        View = new WebView2 { Dock = DockStyle.Fill, Visible = false };
    }

    public async Task InitializeAsync()
    {
        try
        {
            await View.EnsureCoreWebView2Async(environment);
            if (disposed) return;
            var core = View.CoreWebView2;
            SetMemoryTarget(owner.Visible);
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsWebMessageEnabled = false;
            externalLinkMenu = new ExternalLinkMenu(core, Policy, () => IsActive, url => owner.OpenExternal(this, url));
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.DownloadStarting += (_, e) =>
            {
                e.Cancel = true;
                NavigationLog.Write(Provider.Id, "download", Parse(e.DownloadOperation.Uri), "cancel");
            };
            core.LaunchingExternalUriScheme += (_, e) => e.Cancel = true;
            core.NavigationStarting += (_, e) => CheckNavigation(e, true);
            core.FrameNavigationStarting += (_, e) => CheckNavigation(e, false);
            core.NewWindowRequested += (_, e) => owner.HandleNewWindow(this, e);
            core.SourceChanged += (_, _) =>
            {
                CurrentUrl = Parse(core.Source);
                if (hasCommittedPage && !navigationInProgress) SaveCurrentPage();
                owner.SessionChanged(this);
            };
            core.NavigationCompleted += (_, e) =>
            {
                if (e.NavigationId != activeNavigationId) return;
                navigationInProgress = false;
                if (e.IsSuccess)
                {
                    deadline.Finish();
                    hasCommittedPage = true;
                    restoringPage = false;
                    Failure = null;
                    Loading = false;
                    SaveCurrentPage();
                }
                else if (e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
                {
                    deadline.Finish();
                    if (restoringPage) { LoadHome(); return; }
                    Loading = false;
                    if (!hasCommittedPage) Failure = FailureReason(e.WebErrorStatus);
                }
                owner.SessionChanged(this);
            };
            core.ProcessFailed += (_, e) =>
            {
                if (e.ProcessFailedKind is not (CoreWebView2ProcessFailedKind.BrowserProcessExited or CoreWebView2ProcessFailedKind.RenderProcessExited)) return;
                hasCommittedPage = false;
                deadline.Finish();
                NeedsReload = true;
                NeedsRecreate = e.ProcessFailedKind == CoreWebView2ProcessFailedKind.BrowserProcessExited;
                Loading = false;
                owner.BeginInvoke(() => owner.SessionProcessFailed(this));
            };
            View.KeyDown += (_, e) =>
            {
                var keyData = e.KeyData;
                if ((keyData & Keys.Modifiers) == Keys.Control &&
                    (e.KeyCode is >= Keys.D1 and <= Keys.D6 or Keys.R or Keys.Oemcomma))
                {
                    e.Handled = e.SuppressKeyPress = true;
                    owner.BeginInvoke(() => owner.HandleWebShortcut(keyData));
                }
            };
            Initializing = false;
            var restored = LastPage.Restored(settings.GetLastPage(Provider.Id), Policy);
            restoringPage = restored is not null;
            Navigate(restored ?? Provider.Home);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or
                                      System.Runtime.InteropServices.COMException or ObjectDisposedException)
        {
            if (disposed) return;
            Initializing = false;
            Loading = false;
            Failure = $"无法启动网页（{ex.GetType().Name}）";
            owner.SessionChanged(this);
        }
    }

    public void Navigate(Uri url)
    {
        if (!Initializing && !disposed) View.CoreWebView2.Navigate(url.AbsoluteUri);
    }

    public void Reload()
    {
        if (disposed || Initializing) return;
        if (View.CoreWebView2 is null)
        {
            Initializing = true;
            Failure = null;
            owner.SessionChanged(this);
            _ = InitializeAsync();
            return;
        }
        NeedsReload = false;
        if (Failure is not null || !hasCommittedPage) LoadHome();
        else View.CoreWebView2.Reload();
    }

    public void PrepareForDisplay()
    {
        if (NeedsReload || Failure is not null) Reload();
    }

    public void SetMemoryTarget(bool visible)
    {
        if (disposed) return;
        try
        {
            if (View.CoreWebView2 is { } core)
                core.MemoryUsageTargetLevel = visible ? CoreWebView2MemoryUsageTargetLevel.Normal : CoreWebView2MemoryUsageTargetLevel.Low;
        }
        catch (System.Runtime.InteropServices.COMException)
        { NavigationLog.Write(Provider.Id, "memory-target", null, "failed"); }
    }

    public void CheckTimeout(TimeSpan now)
    {
        if (disposed || !Loading || !deadline.HasExpired(now)) return;
        deadline.Finish();
        Loading = false;
        navigationInProgress = false;
        try { View.CoreWebView2.Stop(); }
        catch (System.Runtime.InteropServices.COMException)
        {
            NeedsReload = true;
            Failure = "网页进程不可用";
            owner.SessionChanged(this);
            return;
        }
        if (restoringPage) { LoadHome(); return; }
        Failure = "网络超时";
        owner.SessionChanged(this);
    }

    public void SaveCurrentPage()
    {
        if (disposed || Initializing || !hasCommittedPage || navigationInProgress) return;
        var saved = LastPage.Saved(CurrentUrl, Policy);
        if (saved is not null) settings.SaveLastPage(Provider.Id, saved);
    }

    public void InvalidateAfterBrowserExit()
    {
        hasCommittedPage = false;
        navigationInProgress = false;
        deadline.Finish();
    }

    public void Dispose()
    {
        if (disposed) return;
        SaveCurrentPage();
        disposed = true;
        externalLinkMenu?.Dispose();
        View.Dispose();
    }

    private void LoadHome()
    {
        restoringPage = false;
        Failure = null;
        Navigate(Provider.Home);
    }

    private void CheckNavigation(CoreWebView2NavigationStartingEventArgs e, bool topLevel)
    {
        var url = Parse(e.Uri);
        var source = CurrentUrl;
        var decision = Policy.Action(url, topLevel, e.IsUserInitiated && !e.IsRedirected, null, false, source);
        if (decision != NavigationDecision.Allow)
        {
            e.Cancel = true;
            if (topLevel) owner.NavigationBlocked(this, url, decision);
        }
        else if (topLevel)
        {
            activeNavigationId = e.NavigationId;
            navigationInProgress = true;
            if (!hasCommittedPage)
            {
                deadline.Start(Stopwatch.GetElapsedTime(0));
                Loading = true;
                LoadingStarted = DateTimeOffset.UtcNow;
                Failure = null;
            }
            owner.SessionChanged(this);
        }
        NavigationLog.Write(Provider.Id, topLevel ? "main-action" : "frame-action", url,
            decision == NavigationDecision.Browser ? "cancel-unknown-method" : decision.ToString().ToLowerInvariant());
    }

    internal static Uri? Parse(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var url) ? url : null;

    private static string FailureReason(CoreWebView2WebErrorStatus status) => status switch
    {
        CoreWebView2WebErrorStatus.Timeout => "网络超时",
        CoreWebView2WebErrorStatus.Disconnected => "没有网络连接",
        CoreWebView2WebErrorStatus.CannotConnect or CoreWebView2WebErrorStatus.HostNameNotResolved or
            CoreWebView2WebErrorStatus.ConnectionAborted or CoreWebView2WebErrorStatus.ConnectionReset => "连不上服务器",
        _ => $"加载失败（{status}）"
    };
}
