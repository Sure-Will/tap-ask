using System.Text.Json;

namespace TapAsk.Core;

public sealed record Provider(string Id, string Name, Uri Home, string[] Hosts);

public sealed record ProviderCatalog(string[] IdentityHosts, Provider[] Providers)
{
    public static ProviderCatalog Load(string json)
    {
        var catalog = JsonSerializer.Deserialize<ProviderCatalog>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidDataException("服务商目录为空。");

        if (catalog.Providers is not { Length: > 0 } || catalog.IdentityHosts is null)
            throw new InvalidDataException("服务商目录必须包含服务商和登录主机列表。");

        var ids = new HashSet<string>(StringComparer.Ordinal);
        var identities = new HashSet<string>(catalog.IdentityHosts, StringComparer.OrdinalIgnoreCase);
        var hosts = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var provider in catalog.Providers)
        {
            if (provider is null || string.IsNullOrWhiteSpace(provider.Id) ||
                string.IsNullOrWhiteSpace(provider.Name) || provider.Home is null ||
                provider.Hosts is not { Length: > 0 })
                throw new InvalidDataException("服务商目录包含不完整的条目。");
            if (!ids.Add(provider.Id))
                throw new InvalidDataException($"服务商 id 重复：{provider.Id}。");
            if (!NavigationPolicy.IsHttps(provider.Home) ||
                !provider.Hosts.Contains(provider.Home.IdnHost, StringComparer.OrdinalIgnoreCase))
                throw new InvalidDataException($"服务商 {provider.Id} 的首页无效。");
            foreach (string host in provider.Hosts)
            {
                if (identities.Contains(host))
                    throw new InvalidDataException($"服务商 {provider.Id} 的主机与登录主机重叠：{host}。");
                if (hosts.TryGetValue(host, out var owner) && owner != provider.Id)
                    throw new InvalidDataException($"服务商 {owner} 与 {provider.Id} 的主机重叠：{host}。");
                hosts[host] = provider.Id;
            }
        }
        return catalog;
    }
}
