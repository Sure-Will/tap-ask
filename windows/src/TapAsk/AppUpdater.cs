using TapAsk.Core;
using Velopack;
using Velopack.Locators;
using Velopack.Sources;

namespace TapAsk;

internal sealed class AppUpdater(SettingsStore settings)
{
    private readonly UpdateManager? manager = InstallationLayout.HasVelopackMetadata(AppContext.BaseDirectory)
        ? new(new GithubSource("https://github.com/Sure-Will/tap-ask", null, false), locator: new UpdateLocator(VelopackLocator.Current))
        : null;
    private readonly CancellationTokenSource stopping = new();
    private bool checking;
    public bool Enabled => settings.AutoUpdateEnabled;
    public bool IsInstalled => manager?.IsInstalled == true;
    public bool HasPendingUpdate => IsInstalled && manager?.UpdatePendingRestart is not null;
    public string Status { get; private set; } = "";

    public void SetEnabled(bool enabled) => settings.SaveAutoUpdateEnabled(enabled);

    public async Task CheckIfDueAsync()
    {
        if (IsInstalled && UpdateSchedule.ShouldCheck(Enabled, settings.LastUpdateCheck, DateTimeOffset.UtcNow))
            await CheckAsync(interactive: false);
    }

    public async Task CheckAsync(bool interactive)
    {
        if (checking) return;
        if (manager is null || !manager.IsInstalled)
        {
            if (interactive) MessageBox.Show("源码运行版不支持自动更新。", "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }
        checking = true;
        settings.SaveLastUpdateCheck(DateTimeOffset.UtcNow);
        Status = "正在检查更新…";
        try
        {
            var update = await manager.CheckForUpdatesAsync().WaitAsync(TimeSpan.FromSeconds(30), stopping.Token);
            if (update is null)
            {
                Status = "已是最新版本";
                if (interactive) MessageBox.Show(Status, "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            Status = "正在下载更新…";
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stopping.Token);
            timeout.CancelAfter(TimeSpan.FromMinutes(10));
            await manager.DownloadUpdatesAsync(update, cancelToken: timeout.Token);
            Status = "更新已下载，可从托盘菜单立即安装";
            if (interactive) MessageBox.Show(Status, "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex) when (ex is not OutOfMemoryException and not StackOverflowException)
        {
            if (stopping.IsCancellationRequested) return;
            Status = "检查或下载更新失败";
            NavigationLog.Write("app", "update", null, ex.GetType().Name);
            if (interactive) MessageBox.Show(Status, "TapAsk", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        finally { checking = false; }
    }

    public bool PrepareExit(bool restart, bool startHidden)
    {
        if (manager is not null && manager.IsInstalled && manager.UpdatePendingRestart is { } pending)
        {
            // Only hand off immediately before exit: Velopack waits at most 60 seconds.
            manager.WaitExitThenApplyUpdates(pending, silent: true, restart: restart,
                restartArgs: restart && startHidden ? ["--background"] : null);
        }
        else if (restart) return false;
        stopping.Cancel();
        return true;
    }
}
