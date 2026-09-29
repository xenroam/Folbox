import AppKit
import SwiftUI

@MainActor
final class InternalDragCoordinator {
    static let shared = InternalDragCoordinator()

    private(set) var instanceID: UUID?
    private(set) var filePaths: [String] = []
    var handledInternally = false

    private init() {}

    func begin(instanceID: UUID, filePaths: [String]) {
        self.instanceID = instanceID
        self.filePaths = filePaths
        handledInternally = false
    }

    func end() {
        instanceID = nil
        filePaths = []
        handledInternally = false
    }
}

struct PanelInteractiveAreasKey: PreferenceKey {
    static var defaultValue: [CGRect] { [] }

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func interactiveArea() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelInteractiveAreasKey.self,
                    value: [proxy.frame(in: .named(PanelCoordinateSpace.name))]
                )
            }
        )
    }
}

struct PanelDragAreasKey: PreferenceKey {
    static var defaultValue: [CGRect] { [] }

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func windowDragArea() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelDragAreasKey.self,
                    value: [proxy.frame(in: .named(PanelCoordinateSpace.name))]
                )
            }
        )
    }
}

struct PanelSlotFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

extension View {
    func slotFrame(_ index: Int) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelSlotFramesKey.self,
                    value: [index: proxy.frame(in: .named(PanelCoordinateSpace.name))]
                )
            }
        )
    }
}

enum PanelCoordinateSpace {
    static let name = "Panel"
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PanelDragHandleView: NSViewRepresentable {
    let excludedRects: [CGRect]
    let slotFrames: [Int: CGRect]
    let snapProvider: (CGRect) -> CGPoint
    let onDragEnded: (CGPoint) -> Void
    let onDropRequest: ([URL], Int?) -> Bool
    let onDropTargetedChange: (Bool) -> Void
    var onBackgroundMouseDown: (() -> Void)?
    var onBackgroundClick: (() -> Void)?
    var windowDragRects: [CGRect] = []
    var allowsRubberBandSelection = false
    var onRubberBandChanged: ((CGRect?) -> Void)?
    var previewPayloadProvider: (() -> PreviewPayload)?

    func makeNSView(context: Context) -> PanelDragNSView {
        let view = PanelDragNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PanelDragNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: PanelDragNSView) {
        view.excludedRects = excludedRects
        view.slotFrames = slotFrames
        view.snapProvider = snapProvider
        view.onDragEnded = onDragEnded
        view.onDropRequest = onDropRequest
        view.onDropTargetedChange = onDropTargetedChange
        view.onBackgroundMouseDown = onBackgroundMouseDown
        view.onBackgroundClick = onBackgroundClick
        view.windowDragRects = windowDragRects
        view.allowsRubberBandSelection = allowsRubberBandSelection
        view.onRubberBandChanged = onRubberBandChanged
        view.previewProvider = previewPayloadProvider
    }
}

final class PanelDragNSView: OverlayNSView {
    var snapProvider: ((CGRect) -> CGPoint)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onBackgroundMouseDown: (() -> Void)?
    var onBackgroundClick: (() -> Void)?
    var windowDragRects: [CGRect] = []

    private static let clickTolerance: CGFloat = 5

    private var mouseStart: NSPoint = .zero
    private var windowStart: NSPoint = .zero
    private var isMovingWindow = false
    private var didMoveSinceMouseDown = false

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }

        window.makeFirstResponder(self)
        onBackgroundMouseDown?()
        didMoveSinceMouseDown = false
        mouseStart = NSEvent.mouseLocation

        let local = convert(event.locationInWindow, from: nil)
        guard isInWindowDragRegion(local) else {
            isMovingWindow = false
            if allowsRubberBandSelection {
                beginRubberBand(at: local)
            }
            return
        }

        windowStart = window.frame.origin
        isMovingWindow = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }

        let current = NSEvent.mouseLocation
        if hypot(current.x - mouseStart.x, current.y - mouseStart.y) > Self.clickTolerance {
            didMoveSinceMouseDown = true
        }

        guard isMovingWindow else {
            if allowsRubberBandSelection {
                updateRubberBand(to: convert(event.locationInWindow, from: nil))
            }
            return
        }

        guard didMoveSinceMouseDown else { return }

        let proposedOrigin = CGPoint(
            x: windowStart.x + (current.x - mouseStart.x),
            y: windowStart.y + (current.y - mouseStart.y)
        )
        let proposedFrame = CGRect(origin: proposedOrigin, size: window.frame.size)
        let resolvedOrigin = snapProvider?(proposedFrame) ?? proposedOrigin

        if resolvedOrigin != window.frame.origin {
            window.setFrameOrigin(resolvedOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let window else { return }

        guard isMovingWindow else {
            endRubberBand()
            if !didMoveSinceMouseDown {
                onBackgroundClick?()
            }
            return
        }

        isMovingWindow = false
        if didMoveSinceMouseDown {
            onDragEnded?(window.frame.origin)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let contentView = window?.contentView, let scrollView = Self.findScrollView(in: contentView) else {
            super.scrollWheel(with: event)
            return
        }

        scrollView.scrollWheel(with: event)
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }

        return nil
    }

    private func isInWindowDragRegion(_ point: NSPoint) -> Bool {
        guard !windowDragRects.isEmpty else { return false }
        let flipped = CGPoint(x: point.x, y: bounds.height - point.y)
        return windowDragRects.contains(where: { $0.contains(flipped) })
    }
}
