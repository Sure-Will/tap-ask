using System.ComponentModel;
using System.Diagnostics;

namespace TapAsk;

internal static class ExternalBrowser
{
    public static bool Open(Uri url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
        {
            return false;
        }
    }
}
