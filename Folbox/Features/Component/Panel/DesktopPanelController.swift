import AppKit
import Combine
import SwiftUI

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum ScrollTuning {
    /// Minimum gap between two scroll-triggered toggles.
    static let toggleCooldown: TimeInterval = 0.25
}

@MainActor
final class DesktopPanelController: NSObject, ObservableObject {
    static let shared = DesktopPanelController()

    private let store = ComponentStore.shared
    private var componentPanels: [UUID: NSPanel] = [:]
    private var outsideClickMonitors: [Any] = []
    private var scrollMonitors: [Any] = []
    private var lastScrollToggleAt = Date.distantPast
    private var anchorFrames: [UUID: NSRect] = [:]
    private var panelIDsByWindow: [ObjectIdentifier: UUID] = [:]
    private var animatingPanelIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []
    private var panelsInForegroundMode = false

    @Published private(set) var expandedInstanceIDs: Set<UUID> = []
    @Published private(set) var backgroundExpandedInstanceIDs: Set<UUID> = []
    @Published private(set) var selectionResetTokens: [UUID: Int] = [:]

    private override init() {
        super.init()

        store.$instances
            .receive(on: RunLoop.main)
            .sink { [weak self] instances in
                self?.syncPanels(with: instances)
            }
            .store(in: &cancellables)

        SettingsStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.syncPanels(with: self.store.instances, animated: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLayoutForCurrentResolutionProfile()
            }
            .store(in: &cancellables)
    }

    func restorePanels() {
        for instance in store.instances {
            showPanel(for: instance.id)
        }
    }

    func togglePanelsToForegroundMode() {
        if panelsInForegroundMode {
            applyDefocusBehavior()
            return
        }

        panelsInForegroundMode = true
        syncPanels(with: store.instances, animated: false)
        updateOutsideClickMonitoring()
    }

    func refreshPanelLayouts(animated: Bool = false) {
        syncPanels(with: store.instances, animated: animated)
    }

    func showPanel(for id: UUID) {
        if let panel = componentPanels[id] {
            panel.orderFrontRegardless()
            return
        }

        guard let instance = store.instance(with: id) else { return }

        let hostingView = FirstMouseHostingView(
            rootView: ComponentWindowView(instanceID: id)
                .environmentObject(store)
                .environmentObject(SettingsStore.shared)
                .environmentObject(self)
        )
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layerContentsRedrawPolicy = .duringViewResize

        let size = panelSize(for: instance, expanded: expandedInstanceIDs.contains(id))
        let panel = Panel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = expandedInstanceIDs.contains(id) ? Self.expandedLevel : Self.desktopLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.setFrameOrigin(restoredOrigin(for: id, size: size) ?? defaultOrigin(for: size))
        panel.delegate = self
        panel.orderFrontRegardless()

        componentPanels[id] = panel
        panelIDsByWindow[ObjectIdentifier(panel)] = id
        anchorFrames[id] = panel.frame
        startScrollMonitoring()
    }

    func closePanel(for id: UUID) {
        expandedInstanceIDs.remove(id)
        backgroundExpandedInstanceIDs.remove(id)
        if let panel = componentPanels[id] {
            panelIDsByWindow[ObjectIdentifier(panel)] = nil
            panel.delegate = nil
            panel.close()
        }
        componentPanels[id] = nil
        anchorFrames[id] = nil
        selectionResetTokens[id] = nil
        animatingPanelIDs.remove(id)
        updateOutsideClickMonitoring()

        if componentPanels.isEmpty {
            stopScrollMonitoring()
        }
    }

    func isExpanded(_ id: UUID) -> Bool {
        expandedInstanceIDs.contains(id)
    }

    func isBackgroundExpanded(_ id: UUID) -> Bool {
        backgroundExpandedInstanceIDs.contains(id)
    }

    func toggleExpansion(for id: UUID) {
        guard store.instance(with: id) != nil else { return }
        componentPanels[id]?.orderFrontRegardless()

        let isExpanding: Bool
        if expandedInstanceIDs.contains(id) {
            expandedInstanceIDs.remove(id)
            isExpanding = false
        } else {
            expandedInstanceIDs.insert(id)
            isExpanding = true
        }

        // Keep expand behavior immediate; collapse level is adjusted after resize completes.
        if isExpanding {
            syncPanelLevel(for: id)
        }

        syncPanels(with: store.instances)
        updateOutsideClickMonitoring()
    }

    func setExpansion(for id: UUID, expanded: Bool) {
        guard store.instance(with: id) != nil else { return }
        let isCurrentlyExpanded = expandedInstanceIDs.contains(id)
        guard isCurrentlyExpanded != expanded else { return }
        toggleExpansion(for: id)
    }

    func collapseAllExpandedPanels() {
        collapseExpandedPanels(except: nil)
    }

    func collapseExpandedPanels(except preservedID: UUID?) {
        let idsToCollapse = expandedInstanceIDs.filter { $0 != preservedID }
        if idsToCollapse.isEmpty {
            if expandedInstanceIDs.isEmpty {
                resetForegroundModeIfNeeded()
            }
            updateOutsideClickMonitoring()
            return
        }

        expandedInstanceIDs.subtract(idsToCollapse)

        for id in idsToCollapse {
            guard let instance = store.instance(with: id) else { continue }
            animatePanel(for: id, to: panelSize(for: instance, expanded: false))
        }

        updateOutsideClickMonitoring()
        if expandedInstanceIDs.isEmpty {
            resetForegroundModeIfNeeded()
        }
    }

    private func updateOutsideClickMonitoring() {
        if expandedInstanceIDs.isEmpty && !panelsInForegroundMode {
            stopOutsideClickMonitoring()
        } else {
            startOutsideClickMonitoring()
        }
    }

    private func startScrollMonitoring() {
        guard scrollMonitors.isEmpty else { return }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScroll(event)
            }
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScroll(event)
            }
            return event
        }

        let globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resetSelectionsOutsideClickTarget()
            }
        }

        let localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.resetSelectionsOutsideClickTarget()
            }
            return event
        }

        scrollMonitors = [globalMonitor, localMonitor, globalClickMonitor, localClickMonitor].compactMap { $0 }
    }

    private func resetSelectionsOutsideClickTarget() {
        let location = NSEvent.mouseLocation

        for (id, panel) in componentPanels where !panel.frame.contains(location) {
            selectionResetTokens[id, default: 0] += 1
        }
    }

    private func stopScrollMonitoring() {
        for monitor in scrollMonitors {
            NSEvent.removeMonitor(monitor)
        }
        scrollMonitors = []
    }

    private func handleScroll(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        guard let id = panelIDForScroll(at: location, event: event) else { return }
        guard let instance = store.instance(with: id) else { return }

        let expanded = expandedInstanceIDs.contains(id)
        if expanded, contentOverflows(instance) {
            return
        }

        let rawDelta = event.scrollingDeltaY
        guard rawDelta != 0 else { return }

        let normalized = event.isDirectionInvertedFromDevice ? -rawDelta : rawDelta
        let scrolledDown = normalized < 0

        let settings = SettingsStore.shared
        let wantsExpand = settings.panelScrollMode == .scrollUpExpands ? !scrolledDown : scrolledDown

        guard wantsExpand != expanded else { return }
        guard Date().timeIntervalSince(lastScrollToggleAt) > ScrollTuning.toggleCooldown else { return }

        lastScrollToggleAt = Date()
        toggleExpansion(for: id)
    }

    private func panelIDForScroll(at location: NSPoint, event: NSEvent) -> UUID? {
        if let window = event.window,
           let id = panelIDsByWindow[ObjectIdentifier(window)],
           let panel = componentPanels[id],
           panel.frame.contains(location),
           isTopmostWindow(panel, at: location) {
            return id
        }

        for window in NSApp.orderedWindows {
            guard let id = panelIDsByWindow[ObjectIdentifier(window)] else { continue }
            guard let panel = componentPanels[id] else { continue }
            if panel.frame.contains(location), isTopmostWindow(panel, at: location) {
                return id
            }
        }

        for (id, panel) in componentPanels where panel.frame.contains(location) {
            if isTopmostWindow(panel, at: location) {
                return id
            }
        }

        return nil
    }

    private func isTopmostWindow(_ panel: NSPanel, at location: NSPoint) -> Bool {
        NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0) == panel.windowNumber
    }

    private func syncPanelLevel(for id: UUID) {
        guard let panel = componentPanels[id] else { return }

        let targetLevel: NSWindow.Level
        if panelsInForegroundMode {
            targetLevel = Self.expandedLevel
        } else {
            targetLevel = expandedInstanceIDs.contains(id) ? Self.expandedLevel : Self.desktopLevel
        }
        guard panel.level != targetLevel else { return }

        panel.level = targetLevel
        if targetLevel == Self.expandedLevel {
            panel.orderFrontRegardless()
        }
    }

    func applyDefocusBehavior() {
        resetForegroundModeIfNeeded()
        collapseAllExpandedPanels()
    }

    private func resetForegroundModeIfNeeded() {
        guard panelsInForegroundMode else { return }
        panelsInForegroundMode = false
        syncPanels(with: store.instances, animated: false)
    }

    private func contentOverflows(_ instance: ComponentInstance) -> Bool {
        let settings = SettingsStore.shared
        let columns = GridMetrics.clamp(settings.expandedColumns)
        let rows = GridMetrics.visibleRowCount(
            fileCount: instance.filePaths.count,
            columns: columns,
            maxRows: settings.gridRows
        )
        return instance.filePaths.count > rows * columns
    }

    private func startOutsideClickMonitoring() {
        guard outsideClickMonitors.isEmpty else { return }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.collapseAllExpandedPanels()
            }
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let collapseGuardPanels: [NSPanel]
                if self.panelsInForegroundMode {
                    collapseGuardPanels = Array(self.componentPanels.values)
                } else {
                    collapseGuardPanels = self.expandedInstanceIDs.compactMap { self.componentPanels[$0] }
                }
                if let window = event.window, collapseGuardPanels.contains(where: { $0 === window }) {
                    return
                }
                self.collapseAllExpandedPanels()
            }
            return event
        }

        outsideClickMonitors = [globalMonitor, localMonitor].compactMap { $0 }
    }

    private func stopOutsideClickMonitoring() {
        for monitor in outsideClickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitors = []
    }

    private func animatePanel(for id: UUID, to size: NSSize, animated: Bool = true) {
        guard let panel = componentPanels[id] else { return }

        panel.setFrame(panel.frame, display: true)

        let settings = SettingsStore.shared
        let anchor = anchorFrames[id] ?? panel.frame
        let originX = settings.panelExpandDirection == .left ? anchor.maxX - size.width : anchor.minX
        var frame = NSRect(x: originX, y: anchor.maxY - size.height, width: size.width, height: size.height)

        if let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin = clampedOrigin(frame.origin, panelSize: frame.size, visibleFrame: visibleFrame)
        }

        guard frame != panel.frame else {
            syncPanelLevel(for: id)
            syncBackgroundExpansion(for: id)
            return
        }

        persistOrigin(frame.origin, panelSize: frame.size, for: id)

        let duration = animated ? settings.panelAnimationDuration : 0
        guard duration > 0 else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
            if !expandedInstanceIDs.contains(id) {
                anchorFrames[id] = panel.frame
            }
            syncPanelLevel(for: id)
            syncBackgroundExpansion(for: id)
            return
        }

        animatingPanelIDs.insert(id)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animatingPanelIDs.remove(id)
                if let panel = self.componentPanels[id] {
                    panel.invalidateShadow()
                    if !self.expandedInstanceIDs.contains(id) {
                        self.anchorFrames[id] = panel.frame
                    }
                }
                self.syncPanelLevel(for: id)
                self.syncBackgroundExpansion(for: id)
            }
        }
    }

    private func syncBackgroundExpansion(for id: UUID) {
        let shouldExpandBackground = expandedInstanceIDs.contains(id)
        let isExpandedBackground = backgroundExpandedInstanceIDs.contains(id)

        guard shouldExpandBackground != isExpandedBackground else { return }

        if shouldExpandBackground {
            backgroundExpandedInstanceIDs.insert(id)
        } else {
            backgroundExpandedInstanceIDs.remove(id)
        }
    }

    private func enforceAnchor(for id: UUID, window: NSWindow) {
        guard !animatingPanelIDs.contains(id), let anchor = anchorFrames[id] else { return }

        let settings = SettingsStore.shared
        let frame = window.frame
        let originX = settings.panelExpandDirection == .left ? anchor.maxX - frame.width : anchor.minX
        let origin = NSPoint(x: originX, y: anchor.maxY - frame.height)

        guard origin != frame.origin else { return }
        window.setFrameOrigin(origin)
    }

    func openInstanceSettings(for id: UUID) {
        ComponentConfigurationWin.shared.showEdit(instanceID: id, instanceStore: store)
    }

    func closeInstanceSettings(for id: UUID) {
        ComponentConfigurationWin.shared.closeEdit(instanceID: id)
    }

    func snappedOrigin(for id: UUID, proposedFrame: CGRect) -> CGPoint {
        guard let screen = screen(containing: proposedFrame) else { return proposedFrame.origin }

        let visibleFrame = screen.visibleFrame
        var xReferences: [CGFloat] = [visibleFrame.minX, visibleFrame.midX, visibleFrame.maxX]
        var yReferences: [CGFloat] = [visibleFrame.minY, visibleFrame.midY, visibleFrame.maxY]

        for (otherID, panel) in componentPanels where otherID != id {
            let frame = panel.frame
            xReferences.append(contentsOf: [frame.minX, frame.maxX])
            yReferences.append(contentsOf: [frame.minY, frame.maxY])
        }

        var origin = proposedFrame.origin

        if let snapped = nearestReference(to: proposedFrame.minX, in: xReferences) {
            origin.x = snapped
        } else if let snapped = nearestReference(to: proposedFrame.maxX, in: xReferences) {
            origin.x = snapped - proposedFrame.width
        }

        if let snapped = nearestReference(to: proposedFrame.minY, in: yReferences) {
            origin.y = snapped
        } else if let snapped = nearestReference(to: proposedFrame.maxY, in: yReferences) {
            origin.y = snapped - proposedFrame.height
        }

        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - proposedFrame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - proposedFrame.height)
        return origin
    }

    func persistPanelOrigin(_ origin: CGPoint, for id: UUID) {
        persistOrigin(
            origin,
            panelSize: componentPanels[id]?.frame.size,
            for: id
        )
        if let panel = componentPanels[id] {
            anchorFrames[id] = panel.frame
        }
    }

    private func applyLayoutForCurrentResolutionProfile() {
        guard !componentPanels.isEmpty else { return }

        let profileKey = currentResolutionProfileKey()

        for (id, panel) in componentPanels {
            guard !animatingPanelIDs.contains(id) else { continue }
            guard let restored = restoredOrigin(for: id, size: panel.frame.size, profileKey: profileKey) else { continue }

            let targetScreen = screen(containing: NSRect(origin: restored, size: panel.frame.size))
                ?? panel.screen
                ?? NSScreen.main
            let visibleFrame = targetScreen?.visibleFrame
            guard let visibleFrame else { continue }

            let targetOrigin = clampedOrigin(restored, panelSize: panel.frame.size, visibleFrame: visibleFrame)
            if targetOrigin != panel.frame.origin {
                panel.setFrameOrigin(targetOrigin)
            }
            anchorFrames[id] = panel.frame
        }
    }

    private func nearestReference(to value: CGFloat, in references: [CGFloat]) -> CGFloat? {
        var best: CGFloat?
        var bestDistance = Self.snapThreshold

        for reference in references {
            let distance = abs(value - reference)
            if distance <= bestDistance {
                bestDistance = distance
                best = reference
            }
        }

        return best
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
    }

    private func syncPanels(with instances: [ComponentInstance], animated: Bool = true) {
        let liveIDs = Set(instances.map(\.id))

        for id in componentPanels.keys where !liveIDs.contains(id) {
            closePanel(for: id)
            closeInstanceSettings(for: id)
        }

        for instance in instances {
            guard let panel = componentPanels[instance.id] else {
                showPanel(for: instance.id)
                continue
            }

            let isExpanded = expandedInstanceIDs.contains(instance.id)
            if isExpanded {
                syncPanelLevel(for: instance.id)
            }

            let size = panelSize(for: instance, expanded: isExpanded)
            if panel.frame.size != size {
                animatePanel(for: instance.id, to: size, animated: animated)
            } else {
                syncPanelLevel(for: instance.id)
                syncBackgroundExpansion(for: instance.id)
            }
        }
    }

    private func panelSize(for instance: ComponentInstance, expanded: Bool) -> NSSize {
        let settings = SettingsStore.shared
        let collapsedColumns = instance.resolvedCollapsedColumns(globalColumns: settings.gridColumns)
        let expandedColumnCount = GridMetrics.clamp(settings.expandedColumns)
        let tile = GridMetrics.tileWidth(for: settings.fileTileSize)
        let tileHeight = GridMetrics.tileHeight(for: settings.fileTileSize)
        let spacing = GridMetrics.spacing
        let padding = GridMetrics.panelPadding
        let titleBar = GridMetrics.titleBarThickness
        let extraWidth = settings.titlePosition.isSide ? titleBar : 0
        let extraHeight = settings.titlePosition.isSide ? 0 : titleBar

        guard expanded else {
            let slots = CGFloat(GridMetrics.visibleSlotCount(fileCount: instance.filePaths.count, columns: collapsedColumns))
            if settings.fileListDisplayMode == .vertical {
                return NSSize(
                    width: tile + padding + extraWidth,
                    height: slots * tileHeight + (slots - 1) * spacing + padding + extraHeight
                )
            }

            return NSSize(
                width: slots * tile + (slots - 1) * spacing + padding + extraWidth,
                height: tileHeight + padding + extraHeight
            )
        }

        let rows = CGFloat(
            GridMetrics.visibleRowCount(
                fileCount: instance.filePaths.count,
                columns: min(max(instance.filePaths.count, 1), expandedColumnCount),
                maxRows: settings.gridRows
            )
        )
        let columnCount = CGFloat(min(max(instance.filePaths.count, 1), expandedColumnCount))

        return NSSize(
            width: columnCount * tile + (columnCount - 1) * spacing + padding + extraWidth,
            height: rows * tileHeight + (rows - 1) * spacing + padding + extraHeight
        )
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSPoint(x: 120, y: 120)
        }

        return NSPoint(
            x: visibleFrame.maxX - size.width - 60,
            y: visibleFrame.maxY - size.height - 60
        )
    }

    private func restoredOrigin(for id: UUID, size: NSSize) -> NSPoint? {
        restoredOrigin(for: id, size: size, profileKey: currentResolutionProfileKey())
    }

    private func restoredOrigin(for id: UUID, size: NSSize, profileKey: String) -> NSPoint? {
        if let profileAnchor = restoredProfileAnchor(for: id, profileKey: profileKey) {
            let resolvedFromAnchor = origin(from: profileAnchor, panelSize: size)
            let targetScreen = screen(containing: NSRect(origin: resolvedFromAnchor, size: size))
                ?? NSScreen.main
            if let visibleFrame = targetScreen?.visibleFrame {
                return clampedOrigin(resolvedFromAnchor, panelSize: size, visibleFrame: visibleFrame)
            }
            return resolvedFromAnchor
        }

        if let profileOrigin = restoredProfileOrigin(for: id, profileKey: profileKey) {
            let targetScreen = screen(containing: NSRect(origin: profileOrigin, size: size))
                ?? NSScreen.main
            if let visibleFrame = targetScreen?.visibleFrame {
                return clampedOrigin(profileOrigin, panelSize: size, visibleFrame: visibleFrame)
            }
            return profileOrigin
        }

        return nil
    }

    private func restoredProfileAnchor(for id: UUID, profileKey: String) -> NSPoint? {
        let defaults = UserDefaults.standard
        let key = Self.profileAnchorKey(for: id, profileKey: profileKey)
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 2 else { return nil }

        return NSPoint(x: values[0], y: values[1])
    }

    private func restoredProfileOrigin(for id: UUID, profileKey: String) -> NSPoint? {
        let defaults = UserDefaults.standard
        let key = Self.profileOriginKey(for: id, profileKey: profileKey)
        guard let values = defaults.array(forKey: key) as? [Double], values.count == 2 else { return nil }

        return NSPoint(x: values[0], y: values[1])
    }

    private func persistOrigin(_ origin: NSPoint, panelSize: NSSize?, for id: UUID) {
        let defaults = UserDefaults.standard
        let profileKey = currentResolutionProfileKey()
        let originKey = Self.profileOriginKey(for: id, profileKey: profileKey)
        defaults.set(
            [Double(origin.x), Double(origin.y)],
            forKey: originKey
        )

        if let panelSize {
            let anchor = anchorPoint(from: origin, panelSize: panelSize)
            let anchorKey = Self.profileAnchorKey(for: id, profileKey: profileKey)
            defaults.set(
                [Double(anchor.x), Double(anchor.y)],
                forKey: anchorKey
            )
        }
    }

    private func origin(from anchor: NSPoint, panelSize: NSSize) -> NSPoint {
        let settings = SettingsStore.shared
        let originX = settings.panelExpandDirection == .left ? anchor.x - panelSize.width : anchor.x
        return NSPoint(x: originX, y: anchor.y - panelSize.height)
    }

    private func anchorPoint(from origin: NSPoint, panelSize: NSSize) -> NSPoint {
        let settings = SettingsStore.shared
        let anchorX = settings.panelExpandDirection == .left ? origin.x + panelSize.width : origin.x
        return NSPoint(x: anchorX, y: origin.y + panelSize.height)
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        let maxX = max(visibleFrame.maxX - panelSize.width, visibleFrame.minX)
        let maxY = max(visibleFrame.maxY - panelSize.height, visibleFrame.minY)
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }

    private func currentResolutionProfileKey() -> String {
        let screens = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX == rhs.frame.minX {
                return lhs.frame.minY < rhs.frame.minY
            }
            return lhs.frame.minX < rhs.frame.minX
        }

        if screens.isEmpty {
            return "screens-0"
        }

        let parts = screens.map { screen in
            let frame = screen.frame
            let visible = screen.visibleFrame
            let scale = Int((screen.backingScaleFactor * 100).rounded())
            return "f\(Int(frame.width.rounded()))x\(Int(frame.height.rounded()))_v\(Int(visible.width.rounded()))x\(Int(visible.height.rounded()))_s\(scale)"
        }

        return "screens-\(screens.count)-\(parts.joined(separator: "|"))"
    }

    private static func profileOriginKey(for id: UUID, profileKey: String) -> String {
        "panel.origin.profile.\(id.uuidString).\(profileKey)"
    }

    private static func profileAnchorKey(for id: UUID, profileKey: String) -> String {
        "panel.anchor.profile.\(id.uuidString).\(profileKey)"
    }

    private static let snapThreshold: CGFloat = 12

    private static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private static var expandedLevel: NSWindow.Level {
        .statusBar
    }
}

extension DesktopPanelController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = panelIDsByWindow[ObjectIdentifier(window)] else {
            return
        }

        enforceAnchor(for: id, window: window)
    }
}
