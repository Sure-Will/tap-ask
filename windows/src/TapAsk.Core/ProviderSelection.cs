namespace TapAsk.Core;

public static class ProviderSelection
{
    public static Provider? Restored(IReadOnlyList<Provider> providers, string? savedId)
    {
        if (savedId is null)
            return providers.FirstOrDefault(provider => provider.Id == "deepseek") ?? providers.FirstOrDefault();
        return providers.FirstOrDefault(provider => provider.Id == savedId) ?? providers.FirstOrDefault();
    }
}
