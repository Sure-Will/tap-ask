import Foundation

public struct ProviderCatalog: Decodable, Sendable {
    public let identityHosts: [String]
    public let providers: [Provider]

    private enum CodingKeys: String, CodingKey { case identityHosts, providers }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identityHosts = try values.decode([String].self, forKey: .identityHosts)
        providers = try values.decode([Provider].self, forKey: .providers)
        guard !providers.isEmpty else { throw ValidationError.noProviders }

        var ids = Set<String>()
        var hostOwners: [String: String] = [:]
        let identities = Set(identityHosts.map { $0.lowercased() })
        for provider in providers {
            guard ids.insert(provider.id).inserted else {
                throw ValidationError.duplicateID(provider.id)
            }
            for host in provider.hosts.map({ $0.lowercased() }) {
                if identities.contains(host) {
                    throw ValidationError.identityHostOverlap(host: host, providerID: provider.id)
                }
                if let owner = hostOwners[host], owner != provider.id {
                    throw ValidationError.providerHostOverlap(host: host, firstID: owner, secondID: provider.id)
                }
                hostOwners[host] = provider.id
            }
        }
    }

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case noProviders
        case duplicateID(String)
        case providerHostOverlap(host: String, firstID: String, secondID: String)
        case identityHostOverlap(host: String, providerID: String)

        public var description: String {
            switch self {
            case .noProviders:
                return "providers.json 必须至少包含一个服务商。"
            case .duplicateID(let id):
                return "服务商 id 重复：\(id)。"
            case .providerHostOverlap(let host, let firstID, let secondID):
                return "服务商 \(firstID) 与 \(secondID) 的 hosts 重叠：\(host)。"
            case .identityHostOverlap(let host, let providerID):
                return "服务商 \(providerID) 的 hosts 与 identityHosts 重叠：\(host)。"
            }
        }
    }
}

public struct Provider: Decodable, Sendable {
    public let id: String
    public let name: String
    public let home: URL
    public let hosts: [String]
}
