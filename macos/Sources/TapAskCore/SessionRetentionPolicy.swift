public struct SessionRetentionPolicy {
    public static let backgroundLifetime: Duration = .seconds(300)

    public private(set) var currentProviderID: String?

    private struct BackgroundPage {
        let providerID: String
        let leftAt: ContinuousClock.Instant
    }

    private var backgroundPages: [BackgroundPage] = []

    public init() {}

    public var nextExpiration: ContinuousClock.Instant? {
        backgroundPages.first.map { $0.leftAt.advanced(by: Self.backgroundLifetime) }
    }

    @discardableResult
    public mutating func didDisplay(_ providerID: String, at now: ContinuousClock.Instant) -> [String] {
        guard currentProviderID != providerID else { return [] }

        backgroundPages.removeAll { $0.providerID == providerID }
        if let currentProviderID {
            backgroundPages.append(BackgroundPage(providerID: currentProviderID, leftAt: now))
        }
        currentProviderID = providerID

        if backgroundPages.count > 1 {
            return [backgroundPages.removeFirst().providerID]
        }
        return []
    }

    public mutating func expire(at now: ContinuousClock.Instant) -> [String] {
        guard let nextExpiration, now >= nextExpiration else { return [] }
        return releaseBackgroundPages()
    }

    public mutating func releaseBackgroundPages() -> [String] {
        let released = backgroundPages.map(\.providerID)
        backgroundPages.removeAll()
        return released
    }

    public mutating func reset() {
        currentProviderID = nil
        backgroundPages.removeAll()
    }
}
