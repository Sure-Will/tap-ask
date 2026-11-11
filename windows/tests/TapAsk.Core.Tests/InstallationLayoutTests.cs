using TapAsk.Core;

namespace TapAsk.Core.Tests;

public sealed class InstallationLayoutTests
{
    [Fact]
    public void OnlyRecognizesAContentDirectoryWithManifestAndParentUpdater()
    {
        var root = Path.Combine(Path.GetTempPath(), "TapAsk-layout-" + Guid.NewGuid().ToString("N"));
        var content = Path.Combine(root, "current");
        Directory.CreateDirectory(content);
        try
        {
            Assert.False(InstallationLayout.HasVelopackMetadata(content));
            File.WriteAllText(Path.Combine(content, "sq.version"), "test");
            Assert.False(InstallationLayout.HasVelopackMetadata(content));
            File.WriteAllText(Path.Combine(root, "Update.exe"), "test");
            Assert.True(InstallationLayout.HasVelopackMetadata(content));
            Assert.True(InstallationLayout.HasVelopackMetadata(content + Path.DirectorySeparatorChar));
            File.Delete(Path.Combine(content, "sq.version"));
            Assert.False(InstallationLayout.HasVelopackMetadata(content));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
