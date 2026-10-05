import AppKit
import SwiftUI

struct ExpandedScrollViewWarmup: View {
    let instance: ComponentInstance

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(GridMetrics.tileWidth(for: SettingsStore.shared.fileTileSize)),
                        spacing: GridMetrics.spacing
                    ),
                    count: GridMetrics.clamp(SettingsStore.shared.expandedColumns)
                ),
                spacing: GridMetrics.spacing
            ) {
                ForEach(0 ..< GridMetrics.visibleSlotCount(fileCount: instance.fileURLs.count, columns: GridMetrics.clamp(SettingsStore.shared.expandedColumns)), id: \.self) { _ in
                    Color.clear
                        .frame(
                            width: GridMetrics.tileWidth(for: SettingsStore.shared.fileTileSize),
                            height: GridMetrics.tileHeight(for: SettingsStore.shared.fileTileSize)
                        )
                }
            }
            .background(OverlayScrollerConfigurator())
        }
        .allowsHitTesting(false)
    }
}

struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerFinderView {
        OverlayScrollerFinderView()
    }

    func updateNSView(_ nsView: OverlayScrollerFinderView, context: Context) {
        nsView.applyOverlayStyle()
    }
}

final class OverlayScrollerFinderView: NSView {
    override var intrinsicContentSize: NSSize { .zero }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverlayStyle()
    }

    override func layout() {
        super.layout()
        applyOverlayStyle()
    }

    func applyOverlayStyle() {
        var view = superview
        while let current = view {
            if let scrollView = current as? NSScrollView {
                if scrollView.scrollerStyle != .overlay {
                    scrollView.scrollerStyle = .overlay
                }
                return
            }
            view = current.superview
        }
    }
}

struct FileSlotView: View {
    @EnvironmentObject private var appSettings: SettingsStore
    @EnvironmentObject private var instanceStore: ComponentStore

    let instanceID: UUID
    let slotIndex: Int
    let fileURL: URL
    let isSelected: Bool
    let selectedURLs: [URL]
    let trashAction: () -> Void
    let dropHandler: ([URL], Int?) -> Bool
    let selectAction: (Bool) -> Void
    let clearSelectionAction: () -> Void
    let previewPayload: () -> PreviewPayload
    let primaryAction: () -> Void
    let selectionMoveAction: (SelectionMoveDirection) -> Void
    let previewSelectionAction: (URL) -> Void

    var body: some View {
        let tileSize = appSettings.fileTileSize
        let cornerRadius = GridMetrics.panelCornerRadius(for: tileSize)
        let nameLineLimit = tileSize <= 100 ? 1 : 2

        VStack(spacing: GridMetrics.fileLabelSpacing(for: tileSize)) {
            FileThumbnailView(url: fileURL, size: GridMetrics.thumbnailSize(for: tileSize))
            Text(displayName(for: fileURL))
                .font(.system(size: GridMetrics.fileNameFontSize(for: tileSize)))
                .lineLimit(nameLineLimit)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GridMetrics.tileContentPadding(for: tileSize))
        .frame(
            width: GridMetrics.tileWidth(for: appSettings.fileTileSize),
            height: GridMetrics.tileHeight(for: appSettings.fileTileSize)
        )
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isSelected ? Color.white.opacity(appSettings.componentOpacity / 5) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    Color.white.opacity(appSettings.showFileTileBorder ? (isSelected ? appSettings.componentOpacity : appSettings.componentOpacity / 5) : 0),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .overlay(alignment: .topTrailing) {
            if instanceStore.hasConfiguredFileShortcut(instanceID: instanceID, filePath: fileURL.path) {
                Image(systemName: "k")
                    .font(.system(size: GridMetrics.shortcutBadgeFontSize(for: tileSize), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(appSettings.componentOpacity / 2))
                    .padding(.top, GridMetrics.shortcutBadgeEdgePadding(for: tileSize))
                    .padding(.trailing, GridMetrics.shortcutBadgeEdgePadding(for: tileSize))
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            FileDragSourceView(
                instanceID: instanceID,
                slotIndex: slotIndex,
                url: fileURL,
                onTrash: trashAction,
                onDropRequest: dropHandler,
                selectedURLs: selectedURLs,
                onSelect: selectAction,
                onClearSelection: clearSelectionAction,
                previewPayloadProvider: previewPayload,
                onPrimaryAction: primaryAction,
                onSelectionMove: selectionMoveAction,
                onPreviewItemChanged: previewSelectionAction
            )
        )
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.lowercased().hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        return name
    }
}

struct EmptySlotView: View {
    @EnvironmentObject private var appSettings: SettingsStore

    var body: some View {
        Color.clear
            .frame(
                width: GridMetrics.tileWidth(for: appSettings.fileTileSize),
                height: GridMetrics.tileHeight(for: appSettings.fileTileSize)
            )
    }
}
