using Microsoft.Win32;
using Velopack;
using Velopack.Sources;
using Velopack.Locators;

namespace TapAsk;

internal static class StartupRegistration
{
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
