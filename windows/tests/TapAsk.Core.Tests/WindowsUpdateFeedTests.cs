using System.Security.Cryptography;
using System.Text;
using Velopack;
using Velopack.Locators;
using Velopack.Logging;
using Velopack.Sources;

namespace TapAsk.Core.Tests;

public class WindowsUpdateFeedTests
{
    [Fact]
    public async Task UpdateSourceDoesNotWriteItsRepositoryUrlToDiagnostics()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"TapAsk.UpdateTests.{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            var logger = new RecordingLogger();
            var locator = new TestVelopackLocator("TapAsk", "0.1.5", directory, logger);
            var source = new GithubSource("https://example.test/private-repository", null, false, new EmptyReleaseDownloader());
            var manager = new UpdateManager(source, locator: new TapAsk.UpdateLocator(locator));

            Assert.Null(await manager.CheckForUpdatesAsync());
            Assert.DoesNotContain(logger.Messages, message => message.Contains("https://", StringComparison.OrdinalIgnoreCase));
        }
        finally { Directory.Delete(directory, recursive: true); }
    }

    [Fact]
    public async Task GithubSourceFindsAndDownloadsWindowsPackageFromMixedRelease()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"TapAsk.UpdateTests.{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            var downloader = new MixedReleaseDownloader();
            var source = new GithubSource("https://github.com/Sure-Will/tap-ask", null, false, downloader);
            var locator = new TestVelopackLocator("TapAsk", "0.1.5", directory, null, null, null, "win");
            var manager = new UpdateManager(source, new UpdateOptions { ExplicitChannel = "win" }, locator);
            var update = await manager.CheckForUpdatesAsync();
            Assert.NotNull(update);
            Assert.Equal("TapAsk-0.1.6-full.nupkg", update.TargetFullRelease.FileName);
            await manager.DownloadUpdatesAsync(update);
            Assert.Equal(downloader.Package, await File.ReadAllBytesAsync(Path.Combine(directory, "TapAsk-0.1.6-full.nupkg")));
            Assert.Contains(downloader.Requests, url => url.EndsWith("/releases.win.json", StringComparison.Ordinal));
            Assert.DoesNotContain(downloader.Requests, url => url.EndsWith("/appcast.xml", StringComparison.Ordinal));
        }
        finally { Directory.Delete(directory, recursive: true); }
    }

    private sealed class MixedReleaseDownloader : IFileDownloader
    {
        public byte[] Package { get; } = Encoding.UTF8.GetBytes("test package bytes");
        public List<string> Requests { get; } = [];

        public Task<string> DownloadString(string url, IDictionary<string, string>? headers = null, double timeout = 30)
        {
            Requests.Add(url);
            if (url.Contains("api.github.com", StringComparison.OrdinalIgnoreCase))
                return Task.FromResult("""
                [{"name":"0.1.6","prerelease":false,"published_at":"2026-11-11T00:00:00Z","assets":[
                  {"name":"appcast.xml","browser_download_url":"https://example.test/appcast.xml"},
                  {"name":"TapAsk-0.1.6-macOS.dmg","browser_download_url":"https://example.test/TapAsk-0.1.6-macOS.dmg"},
                  {"name":"releases.win.json","browser_download_url":"https://example.test/releases.win.json"},
                  {"name":"TapAsk-0.1.6-full.nupkg","browser_download_url":"https://example.test/TapAsk-0.1.6-full.nupkg"}
                ]}]
                """);
            if (url.EndsWith("/releases.win.json", StringComparison.Ordinal))
            {
                var sha1 = Convert.ToHexString(SHA1.HashData(Package));
                var sha256 = Convert.ToHexString(SHA256.HashData(Package));
                return Task.FromResult($$"""{"Assets":[{"PackageId":"TapAsk","Version":"0.1.6","Type":"Full","FileName":"TapAsk-0.1.6-full.nupkg","SHA1":"{{sha1}}","SHA256":"{{sha256}}","Size":{{Package.Length}}}]}""");
            }
            throw new InvalidOperationException($"Unexpected test URL: {url}");
        }

        public async Task<byte[]> DownloadBytes(string url, IDictionary<string, string>? headers = null, double timeout = 30) =>
            Encoding.UTF8.GetBytes(await DownloadString(url, headers, timeout));

        public async Task DownloadFile(string url, string targetFile, Action<int> progress,
            IDictionary<string, string>? headers = null, double timeout = 30, CancellationToken cancelToken = default)
        {
            Requests.Add(url);
            if (!url.EndsWith("/TapAsk-0.1.6-full.nupkg", StringComparison.Ordinal)) throw new InvalidOperationException("Unexpected package URL.");
            await File.WriteAllBytesAsync(targetFile, Package, cancelToken);
        }
    }

    private sealed class RecordingLogger : IVelopackLogger
    {
        public List<string> Messages { get; } = [];
        public void Log(VelopackLogLevel logLevel, string? message, Exception? exception) =>
            Messages.Add($"{message} {exception}");
    }

    private sealed class EmptyReleaseDownloader : IFileDownloader
    {
        public Task<string> DownloadString(string url, IDictionary<string, string>? headers = null, double timeout = 30) => Task.FromResult("[]");
        public Task<byte[]> DownloadBytes(string url, IDictionary<string, string>? headers = null, double timeout = 30) => throw new NotSupportedException();
        public Task DownloadFile(string url, string targetFile, Action<int> progress, IDictionary<string, string>? headers = null, double timeout = 30, CancellationToken cancelToken = default) => throw new NotSupportedException();
    }
}
