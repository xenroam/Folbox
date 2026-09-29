import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let resolvedURL = ComponentStore.shared.resolveStoredFileURL(for: url)
        guard resolvedURL.path == url.path else { return nil }

        let key = cacheKey(for: url, size: size)
        if let cached = cache[key] {
            return cached
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: resolvedURL,
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }

        let image = representation.nsImage
        cache[key] = image
        return image
    }

    private func cacheKey(for url: URL, size: CGFloat) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(size))|\(Int(modified))"
    }
}
