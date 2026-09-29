import AppKit
import SwiftUI

struct FileDragSourceView: NSViewRepresentable {
    let instanceID: UUID
    let slotIndex: Int
    let url: URL
    let onTrash: () -> Void
    let onDropRequest: ([URL], Int?) -> Bool
    var selectedURLs: [URL] = []
    var onSelect: ((Bool) -> Void)?
    var onClearSelection: (() -> Void)?
    var previewPayloadProvider: (() -> PreviewPayload)?

    func makeNSView(context: Context) -> FileDragNSView {
        let view = FileDragNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: FileDragNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: FileDragNSView) {
        view.instanceID = instanceID
        view.slotIndex = slotIndex
        view.url = url
        view.onTrash = onTrash
        view.onDropRequest = onDropRequest
        view.selectedURLs = selectedURLs
        view.onSelect = onSelect
        view.onClearSelection = onClearSelection
        view.previewProvider = previewPayloadProvider
    }
}

final class FileDragNSView: OverlayNSView, NSDraggingSource {
    var instanceID: UUID?
    var slotIndex: Int = 0
    var url: URL?
    var onTrash: (() -> Void)?
    var selectedURLs: [URL] = []
    var onSelect: ((Bool) -> Void)?
    var onClearSelection: (() -> Void)?

    private var didDragSinceMouseDown = false
    private let fileManager = FileManager.default

    override func resolveSlotIndex(at point: NSPoint) -> Int? {
        slotIndex
    }

    override func mouseDown(with event: NSEvent) {
        guard let url else { return }

        window?.makeFirstResponder(self)
        didDragSinceMouseDown = false

        if event.modifierFlags.contains(.option) {
            onSelect?(true)
        } else if !selectedURLs.contains(url) {
            onSelect?(false)
        }

        refreshQuickLookIfVisible()
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDragSinceMouseDown else { return }
        guard !event.modifierFlags.contains(.option) else { return }
        guard let url else { return }

        let singleClickOpensFile = SettingsStore.shared.singleClickOpensFile
        let shouldOpen = singleClickOpensFile ? event.clickCount == 1 : event.clickCount == 2
        guard shouldOpen else { return }

        guard openResolved(url) else { return }
        DesktopPanelController.shared.applyDefocusBehavior()
        onClearSelection?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let url, let instanceID else { return }

        didDragSinceMouseDown = true

        var draggedURLs = selectedURLs.contains(url) ? selectedURLs : [url]
        if draggedURLs.isEmpty {
            draggedURLs = [url]
        }

        InternalDragCoordinator.shared.begin(instanceID: instanceID, filePaths: draggedURLs.map(\.path))

        var items: [NSDraggingItem] = []
        for (offset, draggedURL) in draggedURLs.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: draggedURL as NSURL)
            let offsetRect = bounds.offsetBy(dx: CGFloat(offset) * 6, dy: CGFloat(offset) * -6)
            item.setDraggingFrame(offsetRect, contents: NSWorkspace.shared.icon(forFile: draggedURL.path))
            items.append(item)
        }

        beginDraggingSession(with: items, event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let url else { return nil }
        let resolvedURL = resolvedTargetURL(for: url)
        let isApplicationLink = {
            guard let instanceID else { return false }
            return ComponentStore.shared.isApplicationLink(instanceID: instanceID, filePath: url.path)
        }()

        let menu = NSMenu()
        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.open"), action: #selector(openFile), keyEquivalent: "").target = self

        let openWithItem = NSMenuItem(title: AppLocalization.string("folbox.file_menu.open_with"), action: nil, keyEquivalent: "")
        menu.addItem(openWithItem)
        menu.setSubmenu(openWithMenu(for: resolvedURL), for: openWithItem)

        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.reveal_in_finder"), action: #selector(revealFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.get_info"), action: #selector(showInfo), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.shortcut"), action: #selector(configureShortcut), keyEquivalent: "").target = self

        menu.addItem(.separator())

        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.copy"), action: #selector(copyFileItem), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.copy_file_name"), action: #selector(copyFileName), keyEquivalent: "").target = self
        menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.copy_file_path"), action: #selector(copyFilePath), keyEquivalent: "").target = self

        if !isApplicationLink {
            menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.rename"), action: #selector(renameFile), keyEquivalent: "").target = self
            menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.duplicate"), action: #selector(duplicateFile), keyEquivalent: "").target = self
            menu.addItem(withTitle: AppLocalization.string("folbox.file_menu.compress"), action: #selector(compressFile), keyEquivalent: "").target = self
        }

        menu.addItem(.separator())

        let removeTitle: String
        if isApplicationLink {
            removeTitle = AppLocalization.string("folbox.file_menu.remove_link")
        } else {
            removeTitle = AppLocalization.string("folbox.file_menu.move_to_trash")
        }
        menu.addItem(withTitle: removeTitle, action: #selector(trashFile), keyEquivalent: "").target = self
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let wasHandledInternally = InternalDragCoordinator.shared.handledInternally
        let shouldApplyDefocus = !wasHandledInternally && operation != []

        InternalDragCoordinator.shared.end()

        if shouldApplyDefocus {
            DesktopPanelController.shared.applyDefocusBehavior()
        }

        if operation == .delete, let instanceID {
            for item in session.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [] {
                ComponentStore.shared.trashFile(instanceID: instanceID, filePath: item.path)
            }
            return
        }
        if let instanceID {
            ComponentStore.shared.pruneMissingFiles(instanceID: instanceID)
        }
    }

    @objc private func openFile() {
        guard let url else { return }
        if openResolved(url) {
            DesktopPanelController.shared.applyDefocusBehavior()
        }
    }

    @objc private func revealFile() {
        guard let url else { return }
        let target = resolvedTargetURL(for: url)
        let didAccess = target.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                target.stopAccessingSecurityScopedResource()
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    @discardableResult
    private func openResolved(_ url: URL) -> Bool {
        let target = resolvedTargetURL(for: url)
        let didAccess = target.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                target.stopAccessingSecurityScopedResource()
            }
        }
        return NSWorkspace.shared.open(target)
    }

    private func resolvedTargetURL(for url: URL) -> URL {
        ComponentStore.shared.resolveStoredFileURL(for: url)
    }

    private func openWithMenu(for targetURL: URL) -> NSMenu {
        let submenu = NSMenu(title: AppLocalization.string("folbox.file_menu.open_with"))
        let appURLs = Array(NSWorkspace.shared.urlsForApplications(toOpen: targetURL).prefix(12))

        if appURLs.isEmpty {
            let emptyItem = NSMenuItem(title: AppLocalization.string("folbox.file_menu.no_compatible_apps"), action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return submenu
        }

        for appURL in appURLs {
            let appName = appURL.deletingPathExtension().lastPathComponent
            let item = NSMenuItem(title: appName, action: #selector(openWithApplication(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appURL
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            submenu.addItem(item)
        }

        return submenu
    }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL, let url else { return }
        let target = resolvedTargetURL(for: url)
        let didAccess = target.startAccessingSecurityScopedResource()
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: configuration) { _, _ in
            if didAccess {
                target.stopAccessingSecurityScopedResource()
            }
        }
        DesktopPanelController.shared.applyDefocusBehavior()
    }

    @objc private func showInfo() {
        guard let url else { return }
        let target = resolvedTargetURL(for: url)
        FileInfoWin.shared.show(fileURL: target)
    }

    @objc private func copyFileItem() {
        guard let url else { return }
        let target = resolvedTargetURL(for: url)
        let didAccess = target.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                target.stopAccessingSecurityScopedResource()
            }
        }

        NSPasteboard.general.clearContents()
        let succeeded = NSPasteboard.general.writeObjects([target as NSURL])
        if !succeeded {
            NSSound.beep()
        }
    }

    @objc private func copyFileName() {
        guard let url else { return }
        let target = resolvedTargetURL(for: url)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target.lastPathComponent, forType: .string)
    }

    @objc private func copyFilePath() {
        guard let url else { return }
        let target = resolvedTargetURL(for: url)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target.path, forType: .string)
    }

    @objc private func renameFile() {
        guard let instanceID, let url else { return }

        let sourceURL = resolvedTargetURL(for: url)
        FileRenameWin.shared.show(
            instanceID: instanceID,
            storedFilePath: url.path,
            resolvedFileURL: sourceURL
        )
    }

    @objc private func duplicateFile() {
        guard let url else { return }
        let sourceURL = resolvedTargetURL(for: url)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = uniqueSiblingURL(for: sourceURL, preferredBaseName: sourceURL.deletingPathExtension().lastPathComponent + " copy", pathExtension: sourceURL.pathExtension)
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            NSSound.beep()
        }
    }

    @objc private func compressFile() {
        guard let url else { return }
        let sourceURL = resolvedTargetURL(for: url)
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let parentDirectory = sourceURL.deletingLastPathComponent()
        let archiveURL = uniqueSiblingURL(for: sourceURL, preferredBaseName: sourceURL.lastPathComponent, pathExtension: "zip")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.currentDirectoryURL = parentDirectory
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceURL.lastPathComponent,
            archiveURL.lastPathComponent
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSSound.beep()
            }
        } catch {
            NSSound.beep()
        }
    }

    private func uniqueSiblingURL(for sourceURL: URL, preferredBaseName: String, pathExtension: String) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        var candidate = directory.appendingPathComponent(pathExtension.isEmpty ? preferredBaseName : preferredBaseName + "." + pathExtension)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let name = preferredBaseName + " " + String(index)
            candidate = directory.appendingPathComponent(pathExtension.isEmpty ? name : name + "." + pathExtension)
            index += 1
        }

        return candidate
    }

    @objc private func configureShortcut() {
        guard let instanceID, let url else { return }
        FileShortcutSettingsWin.shared.show(
            instanceID: instanceID,
            filePath: url.path,
            instanceStore: ComponentStore.shared
        )
    }

    @objc private func trashFile() {
        onTrash?()
    }
}
