import AppKit
import TapAskCore
import WebKit

/// Retains a provider's page and delegate while another provider is visible.
@MainActor
final class ProviderSession {
    let policy: NavigationPolicy
    let webDelegate: WebViewDelegate
    let webView: WKWebView
    private let defaults: UserDefaults
    private var restoringLastPage = false
    var needsReloadOnDisplay = false
    private(set) var loadState: PageLoadState = .idle
    var onLoadStateChange: ((PageLoadState) -> Void)?
    var onCommit: (() -> Void)?

    init(provider: Provider, identityHosts: [String], defaults: UserDefaults = .standard,
         websiteDataStore: WKWebsiteDataStore = .default()) {
        self.defaults = defaults
        policy = NavigationPolicy(provider: provider, identityHosts: identityHosts)
        webDelegate = WebViewDelegate(policy: policy)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        webView = webDelegate.makeWebView(configuration: configuration)
        webDelegate.onLoadStateChange = { [weak self] state in
            guard let self else { return }
            if case .failed = state, self.restoringLastPage {
                self.loadHome()
                return
            }
            if state == .loaded { self.restoringLastPage = false }
            self.loadState = state
            self.onLoadStateChange?(state)
        }
        webDelegate.onCommit = { [weak self] url in
            guard let self else { return }
            if let page = LastPage.saved(from: url, policy: self.policy) {
                self.defaults.set(page, forKey: self.lastPageKey)
            }
            self.onCommit?()
        }
        webDelegate.onProcessTermination = { [weak self] action in
            guard let self else { return }
            switch action {
            case .reloadNow: self.reload()
            case .deferUntilShown: self.needsReloadOnDisplay = true
            }
        }
    }

    private var lastPageKey: String { "LastPage.\(policy.provider.id)" }

    func loadInitialPage() {
        guard let page = LastPage.restored(from: defaults.string(forKey: lastPageKey), policy: policy) else {
            loadHome()
            return
        }
        restoringLastPage = true
        webView.load(URLRequest(url: page, timeoutInterval: 20))
    }

    func loadHome() {
        restoringLastPage = false
        webView.load(URLRequest(url: policy.provider.home, timeoutInterval: 20))
    }

    func reload() {
        needsReloadOnDisplay = false
        if case .failed = loadState {
            loadHome()
        } else if webView.url == nil {
            loadInitialPage()
        } else {
            webView.reload()
        }
    }

    func prepareForDisplay() {
        if needsReloadOnDisplay { reload() }
        else if case .failed = loadState { loadHome() }
    }

    /// Release the page's connections without touching persistent website data or LastPage.
    func dispose() {
        webView.stopLoading()
        onLoadStateChange = nil
        onCommit = nil
        webDelegate.onLoadStateChange = nil
        webDelegate.onNavigationNotice = nil
        webDelegate.onCommit = nil
        webDelegate.onProcessTermination = nil
        webDelegate.onCreatePopup = nil
        webDelegate.onClose = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    var title: String {
        guard let url = webView.url else { return "" }
        return policy.isProviderURL(url) ? "" : NavigationPolicy.origin(url)
    }
}
