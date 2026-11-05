import Foundation

public enum LoginPopupCompletionReload: Equatable, Sendable {
    case now(providerID: String)
    case onNextDisplay(providerID: String)
}

/// Completion belongs to the opener, even if another provider is now displayed.
public func loginPopupCompletionReload(openingProviderID: String,
                                       displayedProviderID: String?) -> LoginPopupCompletionReload {
    openingProviderID == displayedProviderID
        ? .now(providerID: openingProviderID)
        : .onNextDisplay(providerID: openingProviderID)
}

/// Keep paths, ports, credentials and OAuth parameters out of the toolbar.
public func loginPopupHostLabel(for url: URL?) -> String {
    url?.host?.lowercased() ?? ""
}
