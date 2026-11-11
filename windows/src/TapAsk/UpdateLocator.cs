using Velopack;
using Velopack.Locators;
using Velopack.Logging;

namespace TapAsk;

// Velopack's update source can include URLs and exception details in its diagnostics.
// Keep the native updater's local path diagnostics, but do not log update-source messages.
internal sealed class UpdateLocator(IVelopackLocator inner) : IVelopackLocator
{
    public string? AppId => inner.AppId;
    public string? RootAppDir => inner.RootAppDir;
    public string? PackagesDir => inner.PackagesDir;
    public string? AppContentDir => inner.AppContentDir;
    public string? AppTempDir => inner.AppTempDir;
    public string? UpdateExePath => inner.UpdateExePath;
    public SemanticVersion? CurrentlyInstalledVersion => inner.CurrentlyInstalledVersion;
    public string? ThisExeRelativePath => inner.ThisExeRelativePath;
    public string? Channel => inner.Channel;
    public string? AppUserModelId => inner.AppUserModelId;
    public IVelopackLogger Log => NullVelopackLogger.Instance;
    public bool IsPortable => inner.IsPortable;
    public IProcessImpl Process => inner.Process;
    public void AddLogger(IVelopackLogger logger) => inner.AddLogger(logger);
    public List<VelopackAsset> GetLocalPackages() => inner.GetLocalPackages();
    public VelopackAsset? GetLatestLocalFullPackage() => inner.GetLatestLocalFullPackage();
    public Guid? GetOrCreateStagedUserId() => inner.GetOrCreateStagedUserId();
}
