using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class ProviderAndLastPageTests
{
    private static readonly ProviderCatalog Catalog = ProviderCatalog.Load(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));
    private static readonly NavigationPolicy Policy = new(Catalog.Providers[0], Catalog.IdentityHosts);

    [Fact]
    public void SharedCatalogContainsExpectedProviders()
    {
        Assert.Equal(new[] { "chatgpt", "claude", "gemini", "deepseek", "grok", "doubao" },
            Catalog.Providers.Select(p => p.Id));
    }

    [Theory]
    [InlineData("{\"identityHosts\":[],\"providers\":[]}")]
    [InlineData("{\"identityHosts\":[],\"providers\":[{\"id\":\"a\",\"name\":\"A\",\"home\":\"https://a.example/\",\"hosts\":[\"a.example\"]},{\"id\":\"a\",\"name\":\"B\",\"home\":\"https://b.example/\",\"hosts\":[\"b.example\"]}]}")]
    [InlineData("{\"identityHosts\":[\"A.EXAMPLE\"],\"providers\":[{\"id\":\"a\",\"name\":\"A\",\"home\":\"https://a.example/\",\"hosts\":[\"a.example\"]}]}")]
    [InlineData("{\"identityHosts\":[],\"providers\":[{\"id\":\"a\",\"name\":\"A\",\"home\":\"https://a.example/\",\"hosts\":[\"a.example\"]},{\"id\":\"b\",\"name\":\"B\",\"home\":\"https://a.example/\",\"hosts\":[\"A.EXAMPLE\"]}]}")]
    public void InvalidCatalogIsRejected(string json) => Assert.Throws<InvalidDataException>(() => ProviderCatalog.Load(json));

    [Fact]
    public void SavesOnlyHomeHostAndPathWithoutSecrets()
    {
        var source = new Uri("https://CHATGPT.COM:443/c/a%2Fb%3Fc%23d?token=secret#message");
        Assert.Equal("https://chatgpt.com/c/a%2Fb%3Fc%23d", LastPage.Saved(source, Policy));
        Assert.Equal("https://chatgpt.com/c/a%2Fb%3Fc%23d", LastPage.Restored(source.OriginalString, Policy)!.OriginalString);
    }

    [Theory]
    [InlineData("http://chatgpt.com/c/one")]
    [InlineData("https://chatgpt.com.attacker.invalid/c/one")]
    [InlineData("https://sub.chatgpt.com/c/one")]
    [InlineData("https://chаtgpt.com/c/one")]
    [InlineData("https://user:secret@chatgpt.com/c/one")]
    [InlineData("https://chatgpt.com:8443/c/one")]
    [InlineData("https://auth.openai.com/login")]
    [InlineData("https://accounts.google.com/login")]
    [InlineData("https://chatgpt.com/c/%zz")]
    [InlineData("https://chatgpt.com/c/a b")]
    [InlineData("not a URL")]
    [InlineData("")]
    public void UnsafeStoredPagesAreRejected(string value) => Assert.Null(LastPage.Restored(value, Policy));
}
