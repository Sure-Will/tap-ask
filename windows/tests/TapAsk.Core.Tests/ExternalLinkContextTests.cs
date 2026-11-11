using TapAsk.Core;

namespace TapAsk.Core.Tests;

public sealed class ExternalLinkContextTests
{
    private static readonly ProviderCatalog Catalog = ProviderCatalog.Load(File.ReadAllText("providers.json"));
    private static readonly NavigationPolicy Policy = new(Catalog.Providers.Single(p => p.Id == "deepseek"), Catalog.IdentityHosts);

    [Fact]
    public void UserSelectedExternalLinkFromAllowedFrameCanOpen()
    {
        var result = ExternalLinkContext.BrowserUrl(Policy, true, "https://example.org/article?a=1", "https://chat.deepseek.com/");
        Assert.Equal("https://example.org/article?a=1", result?.AbsoluteUri);
    }

    [Theory]
    [InlineData(false, "https://example.org/", "https://chat.deepseek.com/")]
    [InlineData(true, "https://chat.deepseek.com/", "https://chat.deepseek.com/")]
    [InlineData(true, "https://example.org/", "https://attacker.example/")]
    [InlineData(true, "http://example.org/", "https://chat.deepseek.com/")]
    [InlineData(true, "https://name@example.org/", "https://chat.deepseek.com/")]
    [InlineData(true, "https://example.org/", "about:blank")]
    [InlineData(true, "not-a-url", "https://chat.deepseek.com/")]
    public void NonLinksAndTargetsOutsidePolicyAreNotOffered(bool hasLink, string link, string frame)
        => Assert.Null(ExternalLinkContext.BrowserUrl(Policy, hasLink, link, frame));
}
