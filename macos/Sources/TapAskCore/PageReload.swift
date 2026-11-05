import Foundation

public enum PageReloadTarget: Equatable, Sendable {
    case provider
    case loginPopup
}

/// A background app's menu command always targets the current provider.
public func pageReloadTarget(isAppActive: Bool, isLoginPopupKeyWindow: Bool) -> PageReloadTarget {
    isAppActive && isLoginPopupKeyWindow ? .loginPopup : .provider
}

/// Retry only the original destination, rechecked against the current top-level policy.
public func loginPopupRetryURL(initialURL: URL?, policy: NavigationPolicy) -> URL? {
    policy.isPanelURL(initialURL) ? initialURL : nil
}

/// Retry and process recovery must not reuse the current URL, request method or body.
public func loginPopupRetryRequest(initialURL: URL?, policy: NavigationPolicy) -> URLRequest? {
    guard let url = loginPopupRetryURL(initialURL: initialURL, policy: policy) else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    return request
}
