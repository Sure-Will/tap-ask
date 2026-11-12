using Microsoft.Win32;
using TapAsk.Core;
using Velopack;
using Velopack.Sources;
using Velopack.Locators;

namespace TapAsk;

internal static class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ApprovalKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

    public static bool IsEnabled()
    {
        using var run = Registry.CurrentUser.OpenSubKey(RunKey);
        return run?.GetValue("TapAsk") is string && !IsDisabledByWindows();
    }

    private static bool IsDisabledByWindows()
    {
        using var approved = Registry.CurrentUser.OpenSubKey(ApprovalKey);
        return approved?.GetValue("TapAsk") is byte[] state && state.Length > 0 && state[0] is 3 or 7;
    }

    public static void SetEnabled(bool enabled)
    {
        if (enabled && IsDisabledByWindows())
            throw new InvalidOperationException("请先在 Windows 启动应用设置中允许 TapAsk。");
        using var run = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
            ?? throw new IOException("无法打开登录启动项。");
        if (enabled)
        {
            var root = InstallationLayout.HasVelopackMetadata(AppContext.BaseDirectory)
                ? VelopackLocator.Current.RootAppDir : null;
            var executable = root is null ? Environment.ProcessPath : Path.Combine(root, "TapAsk.exe");
            if (executable is null || !string.Equals(Path.GetFileName(executable), "TapAsk.exe", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("请从 TapAsk.exe 启动后再设置登录时启动。");
            run.SetValue("TapAsk", $"\"{executable}\" --background", RegistryValueKind.String);
        }
        else run.DeleteValue("TapAsk", throwOnMissingValue: false);
    }

    public static void RegisterFirstInstall()
    {
        var settings = new SettingsStore();
        if (settings.AutoStartAttempted) return;
        settings.SaveAutoStartAttempted();
        try
        {
            var manager = new UpdateManager(new GithubSource("https://github.com/Sure-Will/tap-ask", null, false));
            var root = VelopackLocator.Current.RootAppDir;
            if (!manager.IsInstalled || root is null) return;
            var launcher = Path.Combine(root, "TapAsk.exe");
            using var run = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true)
                ?? throw new IOException("无法打开登录启动项。");
            run.SetValue("TapAsk", $"\"{launcher}\" --background", RegistryValueKind.String);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            NavigationLog.Write("app", "autostart", null, "registration-failed");
        }
    }
}
