using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class ProviderLifecycleTests
{
    private static Provider[] Providers => ProviderCatalog.Load(File.ReadAllText("providers.json")).Providers;

    [Fact]
    public void SavedOrderSkipsUnknownAndDuplicatesAndAppendsNewProviders()
    {
        var ordered = ProviderOrder.Ordered(Providers, ["removed", "grok", "chatgpt", "grok"]);
        Assert.Equal(new[] { "grok", "chatgpt", "claude", "gemini", "deepseek", "doubao" }, ordered.Select(p => p.Id));
    }

    [Fact]
    public void MovingUsesInsertionBoundary()
    {
        Assert.Equal(new[] { "b", "c", "a", "d" }, ProviderOrder.Moving(["a", "b", "c", "d"], 0, 3));
        Assert.Equal(new[] { "c", "a", "b" }, ProviderOrder.Moving(["a", "b", "c"], 2, 0));
    }

    [Fact]
    public void OnlyTheMostRecentBackgroundPageIsKeptAndItExpiresAfterFiveMinutes()
    {
        var policy = new SessionRetentionPolicy();
        Assert.Null(policy.DidDisplay("a", TimeSpan.Zero));
        Assert.Null(policy.DidDisplay("b", TimeSpan.FromSeconds(10)));
        Assert.Null(policy.Expire(TimeSpan.FromSeconds(309)));
        Assert.Equal("a", policy.Expire(TimeSpan.FromSeconds(310)));
        Assert.Null(policy.Expire(TimeSpan.FromSeconds(500)));
        Assert.Equal("b", policy.CurrentProviderId);
    }

    [Fact]
    public void ReturningToPageCancelsItsOldDeadlineAndThirdPageEvictsOldest()
    {
        var policy = new SessionRetentionPolicy();
        policy.DidDisplay("a", TimeSpan.Zero);
        policy.DidDisplay("b", TimeSpan.FromSeconds(1));
        Assert.Null(policy.DidDisplay("a", TimeSpan.FromSeconds(400)));
        Assert.Null(policy.Expire(TimeSpan.FromSeconds(400)));
        Assert.Equal("b", policy.DidDisplay("c", TimeSpan.FromSeconds(401)));
        Assert.Equal("a", policy.ReleaseBackground());
        Assert.Null(policy.NextExpiration);
        Assert.Equal("c", policy.CurrentProviderId);
    }
}
