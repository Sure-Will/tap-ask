import Foundation

public struct ProviderCatalog: Decodable, Sendable {
    public let identityHosts: [String]
    public let providers: [Provider]
}

public struct Provider: Decodable, Sendable {
    public let id: String
    public let name: String
    public let home: URL
    public let hosts: [String]
}
