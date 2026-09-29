import Foundation

enum StorageLocation {
    static func rootDirectoryURL(customURL: URL?) -> URL {
        if let customURL {
            return customURL
        }

        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupportURL
            .appendingPathComponent(AppDefaults.AppInfo.projectName(), isDirectory: true)
    }
}
