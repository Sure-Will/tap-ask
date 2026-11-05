import Foundation

public enum LoginItemRegistration {
    public static func shouldRegister(appBundlePath: String, homeDirectory: String,
                                      hasAttempted: Bool) -> Bool {
        guard !hasAttempted,
              (appBundlePath as NSString).isAbsolutePath,
              (homeDirectory as NSString).isAbsolutePath else { return false }
        let appPath = URL(fileURLWithPath: appBundlePath).standardizedFileURL.path
        let userApplications = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        return ["/Applications", userApplications].contains { appPath.hasPrefix($0 + "/") }
    }
}
