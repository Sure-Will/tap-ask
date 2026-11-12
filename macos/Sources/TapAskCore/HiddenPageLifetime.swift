public struct HiddenPageLifetime {
    public static let duration: Duration = .seconds(1_800)
    public private(set) var deadline: ContinuousClock.Instant?

    public init() {}

    public mutating func hide(at now: ContinuousClock.Instant) {
        if deadline == nil { deadline = now.advanced(by: Self.duration) }
    }

    public mutating func show() { deadline = nil }

    public func hasExpired(at now: ContinuousClock.Instant) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }
}
