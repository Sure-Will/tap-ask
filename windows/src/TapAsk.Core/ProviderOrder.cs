namespace TapAsk.Core;

public static class ProviderOrder
{
    public static Provider[] Ordered(IReadOnlyList<Provider> providers, IEnumerable<string>? savedIds)
    {
        var remaining = providers.ToDictionary(provider => provider.Id, StringComparer.Ordinal);
        var result = new List<Provider>(providers.Count);
        foreach (var id in savedIds ?? [])
            if (remaining.Remove(id, out var provider)) result.Add(provider);
        result.AddRange(providers.Where(provider => remaining.ContainsKey(provider.Id)));
        return result.ToArray();
    }

    public static string[] Moving(IReadOnlyList<string> ids, int from, int to)
    {
        var result = ids.ToList();
        var id = result[from];
        result.RemoveAt(from);
        result.Insert(to > from ? to - 1 : to, id);
        return result.ToArray();
    }
}
