public enum ProviderOrder {
    public static func ordered(_ providers: [Provider], savedIDs: [String]?) -> [Provider] {
        guard let savedIDs else { return providers }
        var remaining = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let saved = savedIDs.compactMap { remaining.removeValue(forKey: $0) }
        return saved + providers.filter { remaining[$0.id] != nil }
    }

    /// `from` is an existing row; `to` is an insertion boundary in 0...ids.count,
    /// matching NSTableView's .above drop operation before removing the source row.
    public static func moving(_ ids: [String], from: Int, to: Int) -> [String] {
        var result = ids
        let id = result.remove(at: from)
        result.insert(id, at: to > from ? to - 1 : to)
        return result
    }
}
