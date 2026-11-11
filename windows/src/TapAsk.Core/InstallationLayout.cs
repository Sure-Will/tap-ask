namespace TapAsk.Core;

public static class InstallationLayout
{
    public static bool HasVelopackMetadata(string contentDirectory)
    {
        var parentDirectory = Directory.GetParent(Path.TrimEndingDirectorySeparator(contentDirectory));
        return parentDirectory is not null
            && File.Exists(Path.Combine(contentDirectory, "sq.version"))
            && File.Exists(Path.Combine(parentDirectory.FullName, "Update.exe"));
    }
}
