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
