public enum PageLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(PageLoadFailure)
}

public enum PageLoadEvent: Equatable, Sendable {
    case start
    case commit
    case fail(domain: String, code: Int)
    case processTerminated
}

public struct PageLoadFailure: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    public var reason: String {
        switch (domain, code) {
        case ("NSURLErrorDomain", -1001): "网络超时"
        case ("NSURLErrorDomain", -1009): "没有网络连接"
        case ("NSURLErrorDomain", -1003), ("NSURLErrorDomain", -1004),
             ("NSURLErrorDomain", -1005), ("NSURLErrorDomain", -1200): "连不上服务器"
        default: "加载失败（\(code)）"
        }
    }
}

/// A committed document remains visible during subsequent navigation failures.
public func nextPageLoadState(from state: PageLoadState, on event: PageLoadEvent) -> PageLoadState {
    switch event {
    case .start:
        return state == .loaded ? .loaded : .loading
    case .commit:
        return .loaded
    case let .fail(domain, code):
        if (domain == "NSURLErrorDomain" && code == -999)
            || (domain == "WebKitErrorDomain" && (code == 102 || code == 204)) {
            return state
        }
        return state == .loaded ? .loaded : .failed(PageLoadFailure(domain: domain, code: code))
    case .processTerminated:
        return .loading
    }
}
