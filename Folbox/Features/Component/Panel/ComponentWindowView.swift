import SwiftUI
import AppKit

struct ComponentWindowView: View {
    @EnvironmentObject private var instanceStore: ComponentStore
    @EnvironmentObject private var appSettings: SettingsStore
    @EnvironmentObject private var panelController: DesktopPanelController

    let instanceID: UUID

    @State private var isDropTargeted = false
    @State private var interactiveRects: [CGRect] = []
    @State private var slotFrames: [Int: CGRect] = [:]
    @State private var dragAreaRects: [CGRect] = []
    @State private var selectedPaths: Set<String> = []
    @State private var importFailureMessage: String?
    @State private var keyboardFocusRequestID = 0

    private var isExpanded: Bool {
        panelController.isExpanded(instanceID)
    }

    private var isBackgroundExpanded: Bool {
        panelController.isBackgroundExpanded(instanceID)
    }

    private func collapsedColumns(for instance: ComponentInstance) -> Int {
        instance.resolvedCollapsedColumns(globalColumns: appSettings.gridColumns)
    }

    private var expandedColumns: Int {
        GridMetrics.clamp(appSettings.expandedColumns)
    }

    private var panelControlIconSize: CGFloat {
        min(max(GridMetrics.fileNameFontSize(for: appSettings.fileTileSize), 10), 15)
    }

    private var panelControlSideLength: CGFloat {
        panelControlIconSize + 6
    }

    private var panelControlPairSpacing: CGFloat {
        4
    }

    private var panelControlGroupSpacing: CGFloat {
        panelControlPairSpacing
    }

    var body: some View {
        Group {
            if let instance = instanceStore.instance(with: instanceID) {
                componentContent(instance: instance)
            } else {
                Text(appSettings.t("folbox.component_panel.not_found"))
                    .padding(20)
                    .frame(minWidth: 320, minHeight: 120)
            }
        }
        .alert(appSettings.t("folbox.component_panel.import_failed_title"), isPresented: importFailurePresented) {
            Button(appSettings.t("folbox.common.ok"), role: .cancel) {}
        } message: {
            Text(importFailureMessage ?? "")
        }
    }

    private func componentContent(instance: ComponentInstance) -> some View {
        let cornerRadius = GridMetrics.panelCornerRadius(for: appSettings.fileTileSize)

        return VStack(spacing: 10) {
            if appSettings.titlePosition == .top {
                header(instance: instance)
            }

            mainRow(instance: instance)

            if appSettings.titlePosition == .bottom {
                header(instance: instance)
                    .hidden()
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .overlay(alignment: .bottom) {
            if appSettings.titlePosition == .bottom {
                header(instance: instance)
                    .padding(12)
            }
        }
        .overlay(alignment: .leading) {
            if appSettings.titlePosition == .left {
                sideHeader(instance: instance)
                    .padding(12)
            }
        }
        .overlay(alignment: .trailing) {
            if appSettings.titlePosition == .right {
                sideHeader(instance: instance)
                    .padding(12)
            }
        }
        .background(
            ZStack {
                Color.white.opacity(0.001)
                if appSettings.panelBlurIntensity > 0 {
                    SwiftBlurBackground(opacity: appSettings.panelBlurIntensity)
                }
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(accentColor(hex: instance.styleColorHex).opacity(isBackgroundExpanded ? appSettings.expandedBackgroundOpacity : appSettings.collapsedBackgroundOpacity))
                    .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
            }
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .coordinateSpace(name: PanelCoordinateSpace.name)
        .onPreferenceChange(PanelInteractiveAreasKey.self) { rects in
            interactiveRects = rects
        }
        .onPreferenceChange(PanelSlotFramesKey.self) { frames in
            slotFrames = frames
        }
        .onPreferenceChange(PanelDragAreasKey.self) { rects in
            dragAreaRects = rects
        }
        .onChange(of: panelController.selectionResetTokens[instanceID] ?? 0) {
            selectedPaths = []
        }
        .overlay(
            PanelDragHandleView(
                excludedRects: interactiveRects,
                slotFrames: slotFrames,
                snapProvider: { proposedFrame in
                    DesktopPanelController.shared.snappedOrigin(for: instanceID, proposedFrame: proposedFrame)
                },
                onDragEnded: { origin in
                    DesktopPanelController.shared.persistPanelOrigin(origin, for: instanceID)
                },
                onDropRequest: { urls, index in
                    handleDrop(urls: urls, targetIndex: index)
                },
                onDropTargetedChange: { targeted in
                    isDropTargeted = targeted
                },
                onBackgroundMouseDown: {
                    selectedPaths = []
                },
                onBackgroundClick: {
                    switch appSettings.panelBackgroundClick {
                    case .expandOnly:
                        guard !panelController.isExpanded(instanceID) else { return }
                        panelController.collapseExpandedPanels(except: instanceID)
                        panelController.toggleExpansion(for: instanceID)
                    case .expandCollapse:
                        panelController.toggleExpansion(for: instanceID)
                    }
                },
                onPrimaryAction: {
                    openRenameForSingleSelection(instance: instance)
                },
                onSelectionMove: { direction in
                    moveSelection(instance: instance, direction: direction)
                },
                onPreviewItemChanged: { previewURL in
                    syncSelectionFromPreview(instance: instance, previewURL: previewURL)
                },
                onPreviewSelectionMove: { previewURL, direction in
                    previewURLAfterMove(instance: instance, currentPreviewURL: previewURL, direction: direction)
                },
                keyboardFocusRequestID: keyboardFocusRequestID,
                windowDragRects: dragAreaRects,
                allowsRubberBandSelection: true,
                onRubberBandChanged: { rect in
                    applyRubberBandSelection(rect: rect, files: instance.fileURLs)
                },
                previewPayloadProvider: {
                    previewPayload(files: instance.fileURLs, anchor: nil)
                }
            )
        )
        .padding(8)
    }

    private func mainRow(instance: ComponentInstance) -> some View {
        HStack(spacing: 10) {
            if appSettings.titlePosition == .left {
                sideHeader(instance: instance)
                    .hidden()
            }

            if isExpanded {
                expandedGrid(instance: instance)
            } else {
                compactSlots(instance: instance)
                    .background(
                        ExpandedScrollViewWarmup(instance: instance)
                            .frame(width: 0, height: 0)
                            .opacity(0)
                            .accessibilityHidden(true)
                    )
            }

            if appSettings.titlePosition == .right {
                sideHeader(instance: instance)
                    .hidden()
            }
        }
    }

    private func handleDrop(urls: [URL], targetIndex: Int?) -> Bool {
        let coordinator = InternalDragCoordinator.shared

        if !coordinator.filePaths.isEmpty, let sourceInstanceID = coordinator.instanceID {
            coordinator.handledInternally = true
            var insertIndex = targetIndex
            for path in coordinator.filePaths {
                instanceStore.transferFile(
                    filePath: path,
                    from: sourceInstanceID,
                    to: instanceID,
                    targetIndex: insertIndex
                )
                if let index = insertIndex {
                    insertIndex = index + 1
                }
            }
            return true
        }

        var failures: [String] = []
        let importedCount = instanceStore.importFiles(urls, to: instanceID, failures: &failures)
        if !failures.isEmpty {
            importFailureMessage = failures.joined(separator: "\n")
        }
        return importedCount > 0
    }

    private var importFailurePresented: Binding<Bool> {
        Binding(
            get: { importFailureMessage != nil },
            set: { if !$0 { importFailureMessage = nil } }
        )
    }

    private func panelControlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: panelControlIconSize, weight: .medium))
            .frame(width: panelControlSideLength, height: panelControlSideLength)
            .foregroundStyle(.white)
            .contentShape(Rectangle())
    }

    private func header(instance: ComponentInstance) -> some View {
        let titleSize = GridMetrics.panelTitleFontSize(for: appSettings.fileTileSize)

        return HStack(spacing: 8) {
            Text(instance.name)
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: panelControlGroupSpacing) {
                if isExpanded {
                    HStack(spacing: panelControlPairSpacing) {
                        Button {
                            openInstanceDirectory()
                        } label: {
                            panelControlIcon("folder")
                        }
                        .buttonStyle(.plain)
                        .opacity(isBackgroundExpanded ? appSettings.componentOpacity / 2 : 0)
                        .allowsHitTesting(isBackgroundExpanded)
                        .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                        .interactiveArea()

                        Button {
                            openInstanceSettings()
                        } label: {
                            panelControlIcon("gearshape")
                        }
                        .buttonStyle(.plain)
                        .opacity(isBackgroundExpanded ? appSettings.componentOpacity / 2 : 0)
                        .allowsHitTesting(isBackgroundExpanded)
                        .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                        .interactiveArea()
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(spacing: panelControlPairSpacing) {
                    if shouldRenderExpandHint(for: instance) {
                        panelControlIcon("ellipsis")
                            .opacity(isBackgroundExpanded ? 0 : appSettings.componentOpacity / 2)
                            .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                            .allowsHitTesting(false)
                    }

                    panelControlIcon("arrow.up.and.down.and.arrow.left.and.right")
                        .opacity(appSettings.componentOpacity / 2)
                        .windowDragArea()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func sideHeader(instance: ComponentInstance) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: panelControlPairSpacing) {
                panelControlIcon("arrow.up.and.down.and.arrow.left.and.right")
                    .opacity(appSettings.componentOpacity / 2)
                    .windowDragArea()

                if shouldRenderExpandHint(for: instance) {
                    panelControlIcon("ellipsis")
                        .opacity(isBackgroundExpanded ? 0 : appSettings.componentOpacity / 2)
                        .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                        .allowsHitTesting(false)
                }
            }

            Spacer(minLength: 0)

            if isExpanded {
                VStack(spacing: panelControlPairSpacing) {
                    Button {
                        openInstanceDirectory()
                    } label: {
                        panelControlIcon("folder")
                    }
                    .buttonStyle(.plain)
                    .opacity(isBackgroundExpanded ? appSettings.componentOpacity / 2 : 0)
                    .allowsHitTesting(isBackgroundExpanded)
                    .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                    .interactiveArea()

                    Button {
                        openInstanceSettings()
                    } label: {
                        panelControlIcon("gearshape")
                    }
                    .buttonStyle(.plain)
                    .opacity(isBackgroundExpanded ? appSettings.componentOpacity / 2 : 0)
                    .allowsHitTesting(isBackgroundExpanded)
                    .animation(.easeInOut(duration: appSettings.panelAnimationDuration), value: isBackgroundExpanded)
                    .interactiveArea()
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func openInstanceDirectory() {
        panelController.applyDefocusBehavior()
        let directoryURL = instanceStore.instanceDirectoryURL(for: instanceID)
        NSWorkspace.shared.open(directoryURL)
    }

    private func openInstanceSettings() {
        panelController.applyDefocusBehavior()
        DesktopPanelController.shared.openInstanceSettings(for: instanceID)
    }

    private func shouldRenderExpandHint(for instance: ComponentInstance) -> Bool {
        guard !isExpanded else { return false }
        let collapsedVisibleCount = GridMetrics.visibleSlotCount(
            fileCount: instance.fileURLs.count,
            columns: collapsedColumns(for: instance)
        )
        return instance.fileURLs.count > collapsedVisibleCount
    }

    private func expandedGrid(instance: ComponentInstance) -> some View {
        let files = instance.fileURLs
        let configuredColumns = expandedColumns
        let columns = min(max(files.count, 1), configuredColumns)
        let maxRows = appSettings.gridRows
        let tileWidth = GridMetrics.tileWidth(for: appSettings.fileTileSize)
        let rows = GridMetrics.visibleRowCount(
            fileCount: files.count,
            columns: columns,
            maxRows: maxRows
        )
        let displayCount = max(files.count, columns * rows)
        let items = Array(
            repeating: GridItem(.fixed(tileWidth), spacing: GridMetrics.spacing),
            count: columns
        )
        let needsScrolling = files.count > configuredColumns * maxRows

        return Group {
            if needsScrolling {
                ScrollView(.vertical) {
                    LazyVGrid(columns: items, spacing: GridMetrics.spacing) {
                        ForEach(0 ..< displayCount, id: \.self) { index in
                            slot(instance: instance, files: files, index: index)
                                .slotFrame(index)
                        }
                    }
                    .background(OverlayScrollerConfigurator())
                }
            } else {
                LazyVGrid(columns: items, spacing: GridMetrics.spacing) {
                    ForEach(0 ..< displayCount, id: \.self) { index in
                        slot(instance: instance, files: files, index: index)
                            .slotFrame(index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func slot(instance: ComponentInstance, files: [URL], index: Int) -> some View {
        if index < files.count {
            let fileURL = files[index]
            let path = fileURL.path

            FileSlotView(
                instanceID: instance.id,
                slotIndex: index,
                fileURL: fileURL,
                isSelected: selectedPaths.contains(path),
                selectedURLs: files.filter { selectedPaths.contains($0.path) },
                trashAction: {
                    let selectedFiles = files.filter { selectedPaths.contains($0.path) }
                    let targets = selectedFiles.count > 1 && selectedFiles.contains(where: { $0.path == path })
                        ? selectedFiles
                        : [fileURL]

                    for target in targets {
                        instanceStore.trashFile(instanceID: instance.id, filePath: target.path)
                    }
                    selectedPaths.subtract(targets.map(\.path))
                },
                dropHandler: { urls, targetIndex in
                    handleDrop(urls: urls, targetIndex: targetIndex)
                },
                selectAction: { toggle in
                    updateSelection(for: path, toggle: toggle)
                },
                clearSelectionAction: {
                    selectedPaths = []
                },
                previewPayload: {
                    previewPayload(files: files, anchor: fileURL)
                },
                primaryAction: {
                    openRenameForSingleSelection(instance: instance)
                },
                selectionMoveAction: { direction in
                    moveSelection(instance: instance, direction: direction)
                },
                previewSelectionAction: { previewURL in
                    syncSelectionFromPreview(instance: instance, previewURL: previewURL)
                },
                previewMoveAction: { previewURL, direction in
                    previewURLAfterMove(instance: instance, currentPreviewURL: previewURL, direction: direction)
                }
            )
            .interactiveArea()
        } else {
            EmptySlotView()
        }
    }

    private func compactSlots(instance: ComponentInstance) -> some View {
        let files = instance.fileURLs
        let slotCount = GridMetrics.visibleSlotCount(fileCount: files.count, columns: collapsedColumns(for: instance))

        return Group {
            if appSettings.fileListDisplayMode == .vertical {
                VStack(spacing: GridMetrics.spacing) {
                    ForEach(0 ..< slotCount, id: \.self) { index in
                        slot(instance: instance, files: files, index: index)
                            .slotFrame(index)
                    }
                }
            } else {
                HStack(spacing: GridMetrics.spacing) {
                    ForEach(0 ..< slotCount, id: \.self) { index in
                        slot(instance: instance, files: files, index: index)
                            .slotFrame(index)
                    }
                }
            }
        }
    }

    private func accentColor(hex: String) -> Color {
        Color(hex: hex) ?? .blue
    }

    private func updateSelection(for path: String, toggle: Bool) {
        if toggle {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
            } else {
                selectedPaths.insert(path)
            }
        } else {
            selectedPaths = [path]
        }
    }

    private func applyRubberBandSelection(rect: CGRect?, files: [URL]) {
        guard let rect else {
            selectedPaths = []
            return
        }

        var matched: Set<String> = []
        for (index, frame) in slotFrames where frame.intersects(rect) && index < files.count {
            matched.insert(files[index].path)
        }
        selectedPaths = matched
    }

    private func previewPayload(files: [URL], anchor: URL?) -> PreviewPayload {
        let selected = files.filter { selectedPaths.contains($0.path) }

        if selected.count > 1 {
            if let anchor, let index = selected.firstIndex(of: anchor) {
                return PreviewPayload(items: selected, index: index)
            }

            if anchor == nil {
                return PreviewPayload(items: selected, index: 0)
            }
        }

        let target = anchor ?? selected.first
        let index = target.flatMap { files.firstIndex(of: $0) } ?? 0
        return PreviewPayload(items: files, index: index)
    }

    private func openRenameForSingleSelection(instance: ComponentInstance) {
        guard selectedPaths.count == 1, let selectedPath = selectedPaths.first else { return }
        guard instance.filePaths.contains(selectedPath) else { return }
        guard !instanceStore.isApplicationLink(instanceID: instance.id, filePath: selectedPath) else { return }

        let storedURL = URL(fileURLWithPath: selectedPath)
        let resolvedURL = instanceStore.resolveStoredFileURL(for: storedURL)
        FileRenameWin.shared.show(
            instanceID: instance.id,
            storedFilePath: selectedPath,
            resolvedFileURL: resolvedURL
        )
    }

    private func moveSelection(instance: ComponentInstance, direction: SelectionMoveDirection) {
        guard selectedPaths.count == 1, let selectedPath = selectedPaths.first else { return }
        let files = instance.fileURLs
        guard !files.isEmpty else { return }
        guard let currentIndex = files.firstIndex(where: { $0.path == selectedPath }) else { return }

        let targetIndex = nextWrappedSelectionIndex(
            currentIndex: currentIndex,
            fileCount: files.count,
            direction: direction
        )
        guard targetIndex != currentIndex else { return }

        syncExpansionMode(for: targetIndex, fileCount: files.count, instance: instance)
        selectedPaths = [files[targetIndex].path]
        requestKeyboardFocus()
    }

    private func nextWrappedSelectionIndex(
        currentIndex: Int,
        fileCount: Int,
        direction: SelectionMoveDirection
    ) -> Int {
        guard fileCount > 0 else { return currentIndex }

        let columns = min(max(fileCount, 1), expandedColumns)
        let candidate: Int
        switch direction {
        case .left:
            candidate = currentIndex - 1
        case .right:
            candidate = currentIndex + 1
        case .up:
            candidate = currentIndex - columns
        case .down:
            let currentRow = currentIndex / columns
            let lastRow = (fileCount - 1) / columns
            if currentRow == lastRow {
                candidate = currentIndex + 1
            } else {
                candidate = currentIndex + columns
            }
        }

        return wrappedIndex(candidate, fileCount: fileCount)
    }

    private func wrappedIndex(_ index: Int, fileCount: Int) -> Int {
        guard fileCount > 0 else { return 0 }
        return ((index % fileCount) + fileCount) % fileCount
    }

    private func syncExpansionMode(for targetIndex: Int, fileCount: Int, instance: ComponentInstance) {
        let collapsedVisibleCount = GridMetrics.visibleSlotCount(
            fileCount: fileCount,
            columns: collapsedColumns(for: instance)
        )
        let shouldBeExpandedMode = targetIndex >= collapsedVisibleCount
        panelController.setExpansion(for: instanceID, expanded: shouldBeExpandedMode)
    }

    private func requestKeyboardFocus() {
        keyboardFocusRequestID &+= 1
    }

    private func syncSelectionFromPreview(instance: ComponentInstance, previewURL: URL) {
        let previewPath = previewURL.path
        guard instance.filePaths.contains(previewPath) else { return }
        selectedPaths = [previewPath]
        requestKeyboardFocus()
    }

    private func previewURLAfterMove(
        instance: ComponentInstance,
        currentPreviewURL: URL,
        direction: SelectionMoveDirection
    ) -> URL? {
        let files = instance.fileURLs
        guard !files.isEmpty else { return nil }
        guard let currentIndex = files.firstIndex(of: currentPreviewURL) ?? files.firstIndex(where: { $0.path == currentPreviewURL.path }) else {
            return nil
        }

        let targetIndex = nextWrappedSelectionIndex(
            currentIndex: currentIndex,
            fileCount: files.count,
            direction: direction
        )
        guard targetIndex != currentIndex else { return nil }

        syncExpansionMode(for: targetIndex, fileCount: files.count, instance: instance)
        let targetURL = files[targetIndex]
        selectedPaths = [targetURL.path]
        requestKeyboardFocus()
        return targetURL
    }
}
