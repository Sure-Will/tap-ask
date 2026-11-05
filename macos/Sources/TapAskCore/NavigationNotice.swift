import Foundation

public enum NavigationNoticeEvent: Equatable, Sendable {
    case action, response, redirect, newWindow
    case download
    case failure(domain: String, code: Int)
    case popupClosed
}

public struct NavigationNotice: Equatable, Sendable {
    public enum Kind: Hashable, Sendable { case blocked, browser }

    public let kind: Kind
    public let host: String
    public let message: String

    fileprivate struct Key: Hashable, Sendable {
        let kind: Kind
        let host: String
    }

    fileprivate var key: Key { Key(kind: kind, host: host) }
}

/// Consumes the existing policy result; it never changes navigation permissions.
/// Callers pass URL.host, not an origin or a full URL.
public func navigationNotice(for event: NavigationNoticeEvent, mainFrame: Bool,
                             decision: NavigationPolicy.Decision, host: String?,
                             providerName: String) -> NavigationNotice? {
    guard mainFrame, let host = host?.lowercased(), !host.isEmpty,
          host.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#@")
            .union(.whitespacesAndNewlines)) == nil else { return nil }
    switch (event, decision) {
    case (.action, .cancel), (.response, .cancel), (.redirect, .cancel), (.newWindow, .cancel):
        return NavigationNotice(kind: .blocked, host: host,
                                message: "已拦截 \(host)：TapAsk 只在浮窗里打开 \(providerName) 和常见登录页")
    case (.action, .browser), (.newWindow, .browser):
        return NavigationNotice(kind: .browser, host: host, message: "已在浏览器中打开 \(host)")
    default:
        // Includes downloads, cancellation failures, normal close and allowed inline windows.
        return nil
    }
}

/// Each window owns one value, including when its visible provider changes.
public struct NavigationNoticeState: Equatable, Sendable {
    public fileprivate(set) var notice: NavigationNotice?
    fileprivate var lastShown: [NavigationNotice.Key: TimeInterval] = [:]

    public init() {}
}

/// `time` is supplied by the caller's monotonic clock, making rate limiting deterministic.
public func nextNavigationNoticeState(from state: NavigationNoticeState,
                                      showing notice: NavigationNotice, at time: TimeInterval) -> NavigationNoticeState {
    var next = state
    next.lastShown = state.lastShown.filter { time - $0.value < 10 }
    next.notice = nil
    guard next.lastShown[notice.key] == nil else { return next }
    next.lastShown[notice.key] = time
    next.notice = notice
    return next
}
