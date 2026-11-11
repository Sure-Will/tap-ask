using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class ProviderSelectionTests
{
    private static readonly ProviderCatalog Catalog = ProviderCatalog.Load(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));

    [Fact]
    public void FirstLaunchSelectsDeepSeekRegardlessOfOrder()
    {
        Assert.Equal("deepseek", ProviderSelection.Restored(Catalog.Providers, null)!.Id);
        Assert.Equal("deepseek", ProviderSelection.Restored(Catalog.Providers.Reverse().ToArray(), null)!.Id);
        Assert.Equal("chatgpt", ProviderSelection.Restored(Catalog.Providers.Where(p => p.Id != "deepseek").ToArray(), null)!.Id);
    }

    [Theory]
    [InlineData("chatgpt", "chatgpt")]
    [InlineData("deepseek", "deepseek")]
    [InlineData("", "chatgpt")]
    [InlineData("removed-provider", "chatgpt")]
    public void ExistingChoiceIsRestoredAndInvalidChoiceUsesFirstProvider(string saved, string expected) =>
        Assert.Equal(expected, ProviderSelection.Restored(Catalog.Providers, saved)!.Id);

    [Fact]
    public void EmptyCatalogReturnsNull() => Assert.Null(ProviderSelection.Restored([], null));
}
