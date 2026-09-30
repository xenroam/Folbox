import Foundation
import Combine

@MainActor
final class DesktopAutoMoveStore: ObservableObject {
    private enum Keys {
        static let isEnabled = "feature.autoMoveDesktopFiles.enabled"
        static let destinationBookmark = "feature.autoMoveDesktopFiles.destinationBookmark"
        static let desktopBookmark = "feature.autoMoveDesktopFiles.desktopBookmark"
    }

    static let shared = DesktopAutoMoveStore()

    private let defaults: UserDefaults
    private let fileManager = FileManager.default
    private var accessedSecurityScopedURLs: Set<URL> = []

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            syncService(triggerImmediateScan: false)
        }
    }

    @Published private(set) var destinationDisplayPath: String?

    private var destinationBookmarkData: Data? {
        didSet {
            defaults.set(destinationBookmarkData, forKey: Keys.destinationBookmark)
        }
    }

    private var desktopBookmarkData: Data? {
        didSet {
            defaults.set(desktopBookmarkData, forKey: Keys.desktopBookmark)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.isEnabled) != nil {
            isEnabled = defaults.bool(forKey: Keys.isEnabled)
        } else {
            isEnabled = AppDefaults.Settings.autoMoveDesktopFilesToStorage
        }

        destinationBookmarkData = defaults.data(forKey: Keys.destinationBookmark)
        desktopBookmarkData = defaults.data(forKey: Keys.desktopBookmark)
        destinationDisplayPath = effectiveDestinationURL().path

        syncService(triggerImmediateScan: false)
    }

    func hasDesktopAccessPermission() -> Bool {
        effectiveDesktopURL() != nil
    }

    func setDesktopAccessURL(_ url: URL) -> Bool {
        guard let desktopRootURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL,
              isSameDirectory(url.standardizedFileURL, desktopRootURL) else {
            return false
        }

        guard let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }

        desktopBookmarkData = bookmarkData
        return resolvedDesktopURL() != nil
    }

    func setDestinationURL(_ url: URL) -> Bool {
        guard let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }

        destinationBookmarkData = bookmarkData
        destinationDisplayPath = resolvedDestinationURL()?.path ?? url.standardizedFileURL.path

        if isEnabled {
            syncService(triggerImmediateScan: true)
        }
        return true
    }

    func refreshServiceDestination(triggerImmediateScan: Bool) {
        guard isEnabled else {
            return
        }

        syncService(triggerImmediateScan: triggerImmediateScan)
    }

    private func syncService(triggerImmediateScan: Bool) {
        let destinationURL = effectiveDestinationURL()
        let desktopURL = effectiveDesktopURL()
        destinationDisplayPath = destinationURL.path

        DesktopAutoMoveService.shared.setEnabled(isEnabled, destinationURL: destinationURL, desktopURL: desktopURL)
        if isEnabled {
            DesktopAutoMoveService.shared.refreshConfiguration(destinationURL: destinationURL, desktopURL: desktopURL, triggerImmediateScan: triggerImmediateScan)
        }
    }

    private func effectiveDestinationURL() -> URL {
        if let resolved = resolvedDestinationURL() {
            return resolved.standardizedFileURL
        }

        return StorageLocation
            .rootDirectoryURL(customURL: SettingsStore.shared.resolvedCustomStorageURL())
            .standardizedFileURL
    }

    private func effectiveDesktopURL() -> URL? {
        if let resolved = resolvedDesktopURL() {
            return resolved.standardizedFileURL
        }
        return nil
    }

    private func resolvedDestinationURL() -> URL? {
        guard let bookmarkData = destinationBookmarkData else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if !accessedSecurityScopedURLs.contains(url) {
            if url.startAccessingSecurityScopedResource() {
                accessedSecurityScopedURLs.insert(url)
            }
        }

        if isStale {
            destinationBookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        return url
    }

    private func resolvedDesktopURL() -> URL? {
        guard let bookmarkData = desktopBookmarkData,
              let desktopRootURL = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        let standardized = url.standardizedFileURL
        guard isSameDirectory(standardized, desktopRootURL) else {
            return nil
        }

        if !accessedSecurityScopedURLs.contains(standardized) {
            guard standardized.startAccessingSecurityScopedResource() else {
                return nil
            }
            accessedSecurityScopedURLs.insert(standardized)
        }

        if isStale {
            desktopBookmarkData = try? standardized.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        return standardized
    }

    private func isSameDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        canonicalPath(for: lhs) == canonicalPath(for: rhs)
    }

    private func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
