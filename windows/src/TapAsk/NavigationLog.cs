namespace TapAsk;

internal static class NavigationLog
{
    private const long MaximumBytes = 1024 * 1024;
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TapAsk", "logs");

    public static void Write(string provider, string phase, Uri? url, string result)
    {
        Directory.CreateDirectory(DirectoryPath);
        var path = Path.Combine(DirectoryPath, "tapask.log");
        if (File.Exists(path) && new FileInfo(path).Length >= MaximumBytes)
            File.Move(path, path + ".1", true);
        var host = url is { IsAbsoluteUri: true } && !string.IsNullOrEmpty(url.Host)
            ? url.IdnHost.ToLowerInvariant() : "-";
        File.AppendAllText(path, $"{DateTimeOffset.Now:O} provider={provider} phase={phase} host={host} policy={result}\n");
    }
}
