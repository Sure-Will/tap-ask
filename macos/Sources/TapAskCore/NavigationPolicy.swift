import Foundation

/// Top-level trust is separate from HTTPS resources and subframes (for example, CAPTCHA).
public struct NavigationPolicy: Sendable {
    public enum Decision: String, Equatable, Sendable { case allow, download, browser, cancel }

    public let provider: Provider
    private let providerHosts: Set<String>
    private let panelHosts: Set<String>

    public init(provider: Provider, identityHosts: [String]) {
        self.provider = provider
        providerHosts = Set(provider.hosts)
        panelHosts = Set(provider.hosts).union(identityHosts)
    }

    public static func isHTTPS(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host,
              !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return url.port == nil || url.port == 443
    }

    public func isPanelURL(_ url: URL?) -> Bool {
        Self.isHTTPS(url) && panelHosts.contains(url!.host!.lowercased())
    }

    public func isProviderURL(_ url: URL?) -> Bool {
        Self.isHTTPS(url) && providerHosts.contains(url!.host!.lowercased())
    }

    public static func isGeneratedFile(_ url: URL?) -> Bool {
        ["blob", "data"].contains(url?.scheme?.lowercased() ?? "")
    }

    public func action(url: URL?, topLevel: Bool, clickedLink: Bool, method: String?,
                       wantsDownload: Bool, sourceURL: URL?) -> Decision {
        let generated = Self.isGeneratedFile(url)
        if wantsDownload || (topLevel && generated) {
            return isPanelURL(sourceURL) && (Self.isHTTPS(url) || generated) ? .download : .cancel
        }
        if !topLevel {
            return Self.isHTTPS(url) || ["about:blank", "about:srcdoc"].contains(url?.absoluteString ?? "")
                ? .allow : .cancel
        }
        if isPanelURL(url) { return .allow }
        // Only clicked GET links may leave the app, never forms, scripts or redirects.
        if clickedLink, (method ?? "GET").uppercased() == "GET",
           isPanelURL(sourceURL), Self.isHTTPS(url) { return .browser }
        return .cancel
    }

    public func response(url: URL?, mainFrame: Bool, canDisplay: Bool, attachment: Bool) -> Decision {
        if !canDisplay || attachment {
            return Self.isHTTPS(url) || Self.isGeneratedFile(url) ? .download : .cancel
        }
        if mainFrame { return isPanelURL(url) ? .allow : .cancel }
        return Self.isHTTPS(url) || ["about:blank", "about:srcdoc"].contains(url?.absoluteString ?? "")
            ? .allow : .cancel
    }

    /// Omit credentials, paths and tokens; Foundation supplies ASCII/punycode hosts.
    public static func origin(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host else {
            return "无有效网站来源"
        }
        return "\(scheme)://\(host.lowercased())" + (url.port.map { ":\($0)" } ?? "")
    }
}
