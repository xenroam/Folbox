import Foundation
import Combine

@MainActor
final class DesktopAutoMoveStore: ObservableObject {
    private enum Keys {
        static let isEnabled = "feature.autoMoveDesktopFiles.enabled"
        static let destinationBookmark = "feature.autoMoveDesktopFiles.destinationBookmark"
    }

    static let shared = DesktopAutoMoveStore()

    private let defaults: UserDefaults
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.isEnabled) != nil {
            isEnabled = defaults.bool(forKey: Keys.isEnabled)
        } else {
            isEnabled = AppDefaults.Settings.autoMoveDesktopFilesToStorage
        }

        destinationBookmarkData = defaults.data(forKey: Keys.destinationBookmark)
        destinationDisplayPath = effectiveDestinationURL().path

        syncService(triggerImmediateScan: false)
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
        destinationDisplayPath = destinationURL.path

        DesktopAutoMoveService.shared.setEnabled(isEnabled, destinationURL: destinationURL)
        if isEnabled {
            DesktopAutoMoveService.shared.refreshDestination(destinationURL: destinationURL, triggerImmediateScan: triggerImmediateScan)
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
}
