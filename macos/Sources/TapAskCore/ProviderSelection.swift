public enum ProviderSelection {
    public static func restored(in providers: [Provider], savedID: String?) -> Provider? {
        if savedID == nil {
            return providers.first(where: { $0.id == "deepseek" }) ?? providers.first
        }
        if let savedID, !savedID.isEmpty,
           let provider = providers.first(where: { $0.id == savedID }) {
            return provider
        }
        return providers.first
    }

    /// One-based position, matching the provider menu and its ⌘1–⌘9 shortcuts.
    public static func provider(at number: Int, in providers: [Provider]) -> Provider? {
        guard number > 0, number <= providers.count else { return nil }
        return providers[number - 1]
    }
}
