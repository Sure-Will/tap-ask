using System.Runtime.InteropServices;
using TapAsk.Core;
using Velopack;

namespace TapAsk;

internal static class Program
{
    internal static uint ShowExistingMessage { get; private set; }

    [STAThread]
    private static void Main(string[] args)
    {
        bool firstRun = false;
        if (InstallationLayout.HasVelopackMetadata(AppContext.BaseDirectory))
            VelopackApp.Build().SetAutoApplyOnStartup(false).OnFirstRun(_ => firstRun = true).Run();
        ShowExistingMessage = RegisterWindowMessage("TapAsk.ShowExisting.37B357B3");
        using var mutex = new Mutex(true, @"Local\TapAsk.SingleInstance", out bool firstInstance);
        if (!firstInstance)
        {
            if (!args.Contains("--background", StringComparer.Ordinal))
                PostMessage(new IntPtr(0xffff), ShowExistingMessage, IntPtr.Zero, IntPtr.Zero);
            return;
        }

        if (firstRun) StartupRegistration.RegisterFirstInstall();
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MainForm(args.Contains("--background", StringComparer.Ordinal)));
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
