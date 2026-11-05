import Foundation

public enum LastPage {
    /// Remember only the home host and path, without query data, fragments or credentials.
    public static func saved(from url: URL?, policy: NavigationPolicy) -> String? {
        guard policy.isProviderURL(url), let url,
              url.host?.lowercased() == policy.provider.home.host?.lowercased(),
              let source = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var page = URLComponents()
        page.scheme = "https"
        page.host = url.host?.lowercased()
        page.percentEncodedPath = source.percentEncodedPath
        return page.url?.absoluteString
    }

    /// Revalidate stored values against the current provider and navigation rules.
    public static func restored(from savedValue: String?, policy: NavigationPolicy) -> URL? {
        guard let savedValue, let url = URL(string: savedValue, encodingInvalidCharacters: false),
              let value = saved(from: url, policy: policy) else { return nil }
        return URL(string: value)
    }
}
