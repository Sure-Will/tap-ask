using System.Text.Json;
using TapAsk.Core;

namespace TapAsk.Core.Tests;

public class SharedPolicyTests
{
    private static readonly ProviderCatalog Catalog = ProviderCatalog.Load(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.json")));

    public static IEnumerable<object[]> Cases()
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "policy-cases.json")));
        foreach (string kind in new[] { "isPanelURL", "actions", "responses", "origins" })
            foreach (var item in doc.RootElement.GetProperty(kind).EnumerateArray())
                yield return new object[] { kind, item.GetProperty("id").GetString()!, item.GetRawText() };
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void MatchesSharedCase(string kind, string id, string json)
    {
        using var doc = JsonDocument.Parse(json);
        var item = doc.RootElement;
        string providerId = String(item, "provider") ?? "chatgpt";
        var provider = Catalog.Providers.Single(p => p.Id == providerId);
        var policy = new NavigationPolicy(provider, Catalog.IdentityHosts);
        var url = Url(String(item, "url"));

        switch (kind)
        {
            case "isPanelURL":
                Assert.True(policy.IsPanelUrl(url) == item.GetProperty("expected").GetBoolean(), id);
                break;
            case "actions":
                var action = policy.Action(url, item.GetProperty("topLevel").GetBoolean(),
                    item.GetProperty("clickedLink").GetBoolean(), String(item, "method"),
                    item.GetProperty("wantsDownload").GetBoolean(), Url(String(item, "sourceURL")));
                Assert.True(action.ToString().Equals(String(item, "expected"), StringComparison.OrdinalIgnoreCase),
                    $"{id}: {action}");
                break;
            case "responses":
                var response = policy.Response(url, item.GetProperty("mainFrame").GetBoolean(),
                    item.GetProperty("canDisplay").GetBoolean(), item.GetProperty("attachment").GetBoolean());
                Assert.True(response.ToString().Equals(String(item, "expected"), StringComparison.OrdinalIgnoreCase),
                    $"{id}: {response}");
                break;
            case "origins":
                var origin = NavigationPolicy.Origin(url);
                var expected = String(item, "expected");
                if (expected is not null) Assert.Equal(expected, origin);
                else Assert.DoesNotContain(String(item, "excludes")!, origin);
                if (item.TryGetProperty("isProviderURL", out var own))
                    Assert.True(policy.IsProviderUrl(url) == own.GetBoolean(), id);
                break;
            default:
                throw new InvalidOperationException($"Unknown fixture group: {kind}");
        }
    }

    private static string? String(JsonElement item, string key) =>
        item.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null ? value.GetString() : null;

    private static Uri? Url(string? value) => value is null ? null : new Uri(value, UriKind.Absolute);
}
