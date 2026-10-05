import AppKit
import Quartz
import SwiftUI

enum SelectionMoveDirection {
    case up
    case down
    case left
    case right
}

struct FileThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var image: NSImage?
    @State private var fallbackIcon: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(nsImage: fallbackIcon ?? NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: url.path) {
            let resolvedPath = ComponentStore.shared.resolveStoredFileURL(for: url).path
            fallbackIcon = NSWorkspace.shared.icon(forFile: resolvedPath)
            image = await ThumbnailProvider.shared.thumbnail(for: url, size: size * 2)
        }
    }
}

class OverlayNSView: NSView {
    var excludedRects: [CGRect] = []
    var slotFrames: [Int: CGRect] = [:]
    var onDropRequest: (([URL], Int?) -> Bool)?
    var onDropTargetedChange: ((Bool) -> Void)?
    var allowsRubberBandSelection = false
    var onRubberBandChanged: ((CGRect?) -> Void)?
    var previewProvider: (() -> PreviewPayload)?
    var onPrimaryAction: (() -> Void)?
    var onSelectionMove: ((SelectionMoveDirection) -> Void)?
    var onPreviewItemChanged: ((URL) -> Void)?

    private(set) var previewItemURLs: [URL] = []
    private var pendingPreviewIndex = 0
    private var previewIndexObservation: NSKeyValueObservation?
    private var bandStart: NSPoint?
    private var bandRect: NSRect?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedDragTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.acceptedDragTypes)
    }

    static var acceptedDragTypes: [NSPasteboard.PasteboardType] {
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            toggleQuickLook()
            return
        }

        if let direction = selectionMoveDirection(for: event), let onSelectionMove {
            onSelectionMove(direction)
            return
        }

        if isPrimaryActionEvent(event), let onPrimaryAction {
            onPrimaryAction()
            return
        }

        super.keyDown(with: event)
    }

    private func isPrimaryActionEvent(_ event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard relevantModifiers.isEmpty else { return false }
        return event.keyCode == 36 || event.keyCode == 76
    }

    private func selectionMoveDirection(for event: NSEvent) -> SelectionMoveDirection? {
        let relevantModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard relevantModifiers.isEmpty else { return nil }

        switch event.keyCode {
        case 123:
            return .left
        case 124:
            return .right
        case 125:
            return .down
        case 126:
            return .up
        default:
            return nil
        }
    }

    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }

        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }

        let payload = previewProvider?() ?? PreviewPayload(items: [], index: 0)
        guard !payload.items.isEmpty else { return }

        previewItemURLs = payload.items
        pendingPreviewIndex = min(max(payload.index, 0), payload.items.count - 1)
        window?.makeFirstResponder(self)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func refreshQuickLookIfVisible() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return
        }

        let payload = previewProvider?() ?? PreviewPayload(items: [], index: 0)
        guard !payload.items.isEmpty else { return }

        previewItemURLs = payload.items
        pendingPreviewIndex = min(max(payload.index, 0), payload.items.count - 1)

        window?.makeFirstResponder(self)
        panel.updateController()
        panel.reloadData()
        panel.currentPreviewItemIndex = pendingPreviewIndex
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(pendingPreviewIndex, 0), max(previewItemURLs.count - 1, 0))
        previewIndexObservation = panel.observe(\.currentPreviewItemIndex, options: [.initial, .new]) { [weak self] panel, _ in
            self?.notifyPreviewItemChanged(index: panel.currentPreviewItemIndex)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        previewIndexObservation = nil
        panel.dataSource = nil
        panel.delegate = nil
    }

    private func notifyPreviewItemChanged(index: Int) {
        guard previewItemURLs.indices.contains(index) else { return }
        onPreviewItemChanged?(previewItemURLs[index])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let local = superview.map({ convert(point, from: $0) }), bounds.contains(local) else {
            return nil
        }

        guard !excludedRects.isEmpty else { return self }

        let flipped = CGPoint(x: local.x, y: bounds.height - local.y)
        return excludedRects.contains(where: { $0.contains(flipped) }) ? nil : self
    }

    func resolveSlotIndex(at point: NSPoint) -> Int? {
        guard !slotFrames.isEmpty else { return nil }
        let flipped = CGPoint(x: point.x, y: bounds.height - point.y)
        return slotFrames.first(where: { $0.value.contains(flipped) })?.key
    }

    override func mouseDown(with event: NSEvent) {
        guard allowsRubberBandSelection else { return }
        beginRubberBand(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        guard allowsRubberBandSelection else { return }
        updateRubberBand(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard allowsRubberBandSelection else { return }
        endRubberBand()
    }

    func beginRubberBand(at point: NSPoint) {
        bandStart = point
        bandRect = nil
        onRubberBandChanged?(nil)
        needsDisplay = true
    }

    func updateRubberBand(to point: NSPoint) {
        guard let start = bandStart else { return }

        let rect = NSRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )

        bandRect = rect
        needsDisplay = true
        onRubberBandChanged?(CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
    }

    func endRubberBand() {
        bandStart = nil
        bandRect = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let bandRect else { return }

        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
        bandRect.fill()
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.8).setStroke()
        NSBezierPath(rect: bandRect).stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDropTargetedChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDropTargetedChange?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDropTargetedChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = resolveSlotIndex(at: convert(sender.draggingLocation, from: nil))

        if !InternalDragCoordinator.shared.filePaths.isEmpty {
            return onDropRequest?([], index) ?? false
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        guard !urls.isEmpty else { return false }

        return onDropRequest?(urls, index) ?? false
    }
}

struct PreviewPayload {
    let items: [URL]
    let index: Int
}

extension OverlayNSView: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItemURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewItemURLs.indices.contains(index) else { return nil }
        return previewItemURLs[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, previewItemURLs.count > 1 else { return false }

        switch event.keyCode {
        case 123, 126:
            panel.currentPreviewItemIndex = max(panel.currentPreviewItemIndex - 1, 0)
            return true
        case 124, 125:
            panel.currentPreviewItemIndex = min(panel.currentPreviewItemIndex + 1, previewItemURLs.count - 1)
            return true
        default:
            return false
        }
    }
}
