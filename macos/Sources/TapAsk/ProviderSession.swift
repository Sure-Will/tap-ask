import AppKit
import TapAskCore
import WebKit

/// Retains a provider's page and delegate while another provider is visible.
@MainActor
final class ProviderSession {
    let policy: NavigationPolicy
    let webDelegate: WebViewDelegate
    let webView: WKWebView
    private(set) var loadState: PageLoadState = .idle
    var onLoadStateChange: ((PageLoadState) -> Void)?

    init(provider: Provider, identityHosts: [String]) {
        policy = NavigationPolicy(provider: provider, identityHosts: identityHosts)
        webDelegate = WebViewDelegate(policy: policy)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = webDelegate.makeWebView(configuration: configuration)
        webDelegate.onLoadStateChange = { [weak self] state in
            guard let self else { return }
            self.loadState = state
            self.onLoadStateChange?(state)
        }
    }

    func loadHome() {
        webView.load(URLRequest(url: policy.provider.home, timeoutInterval: 20))
    }

    func reload() {
        if case .failed = loadState {
            loadHome()
        } else if webView.url == nil {
            loadHome()
        } else {
            webView.reload()
        }
    }

    var title: String {
        guard let url = webView.url else { return "" }
        return policy.isProviderURL(url) ? "" : NavigationPolicy.origin(url)
    }
}
