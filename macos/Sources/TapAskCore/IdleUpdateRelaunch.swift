import Foundation

public enum IdleUpdateRelaunch {
    private static let key = "IdleUpdateRelaunchVersion"

    public static func prepare(targetVersion: String, defaults: UserDefaults) {
        defaults.set(targetVersion, forKey: key)
    }

    public static func consume(currentVersion: String?, defaults: UserDefaults) -> Bool {
        guard let target = defaults.string(forKey: key) else { return false }
        defaults.removeObject(forKey: key)
        return !target.isEmpty && target == currentVersion
    }
}
