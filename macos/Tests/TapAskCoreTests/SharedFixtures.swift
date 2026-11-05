import Foundation
import TapAskCore

/// Shared data stays outside the Swift package so every platform can use it.
enum SharedFixtures {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func decode<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
        let url = repositoryRoot.appendingPathComponent("shared").appendingPathComponent(name)
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    static func catalog() throws -> ProviderCatalog {
        try decode("providers.json", as: ProviderCatalog.self)
    }

    static func chatGPTPolicy() throws -> NavigationPolicy {
        try policy(for: nil, in: catalog())
    }

    static func policy(for providerID: String?, in catalog: ProviderCatalog) throws -> NavigationPolicy {
        let id = providerID ?? "chatgpt"
        guard let provider = catalog.providers.first(where: { $0.id == id }) else {
            throw FixtureError.unknownProvider(id)
        }
        return NavigationPolicy(provider: provider, identityHosts: catalog.identityHosts)
    }

    enum FixtureError: Error, Equatable, CustomStringConvertible {
        case unknownProvider(String)

        var description: String {
            switch self {
            case .unknownProvider(let id): return "导航用例引用了不存在的服务商：\(id)。"
            }
        }
    }
}

struct PolicyCases: Decodable {
    let isPanelURL: [PanelURLCase]
    let actions: [ActionCase]
    let responses: [ResponseCase]
    let origins: [OriginCase]

    struct PanelURLCase: Decodable {
        let id: String
        let group: String
        let provider: String?
        let url: String?
        let expected: Bool
    }

    struct ActionCase: Decodable {
        let id: String
        let group: String
        let provider: String?
        let url: String?
        let topLevel: Bool
        let clickedLink: Bool
        let method: String?
        let wantsDownload: Bool
        let sourceURL: String?
        let expected: String
    }

    struct ResponseCase: Decodable {
        let id: String
        let group: String
        let provider: String?
        let url: String?
        let mainFrame: Bool
        let canDisplay: Bool
        let attachment: Bool
        let expected: String
    }

    struct OriginCase: Decodable {
        let id: String
        let group: String
        let provider: String?
        let url: String?
        let expected: String?
        let excludes: String?
        let isProviderURL: Bool?
    }
}
