import SwiftUI
import AppKit

@MainActor
final class FileRenameWin: NSObject, NSWindowDelegate {
    static let shared = FileRenameWin()

    private let fileManager = FileManager.default
    private var window: NSWindow?
    private var context: RenameContext?

    private struct RenameContext {
        let instanceID: UUID
        let storedFilePath: String
        let resolvedFileURL: URL
    }

    private override init() {
        super.init()
    }

    func show(instanceID: UUID, storedFilePath: String, resolvedFileURL: URL) {
        context = RenameContext(
            instanceID: instanceID,
            storedFilePath: storedFilePath,
            resolvedFileURL: resolvedFileURL
        )

        let view = FileRenameView(
            currentName: resolvedFileURL.lastPathComponent,
            onCancel: { [weak self] in
                self?.close()
            },
            onConfirm: { [weak self] newName in
                self?.applyRename(newName: newName)
            }
        )

        if let window {
            replaceContent(of: window, title: AppLocalization.string("folbox.rename.title"), rootView: view)
            activateAndFocus(window)
            return
        }

        self.window = makeWindow(title: AppLocalization.string("folbox.rename.title"), rootView: view)
    }

    func close() {
        window?.close()
        window = nil
        context = nil
    }

    private func applyRename(newName: String) {
        guard let context else { return }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return
        }

        let sourceURL = context.resolvedFileURL
        guard trimmed != sourceURL.lastPathComponent else {
            close()
            return
        }

        let destinationURL = sourceURL.deletingLastPathComponent().appendingPathComponent(trimmed)
        if fileManager.fileExists(atPath: destinationURL.path) {
            NSSound.beep()
            return
        }

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            ComponentStore.shared.updateStoredFilePath(
                instanceID: context.instanceID,
                from: context.storedFilePath,
                to: destinationURL.path
            )
            close()
        } catch {
            NSSound.beep()
        }
    }

    private func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let containerController = makeFrostedContainerController(hostingController: hostingController)

        let window = NSWindow(contentViewController: containerController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = self

        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize
        if size.width > 0, size.height > 0 {
            window.setContentSize(size)
        }

        ScreenManager.center(window)
        activateAndFocus(window)

        return window
    }

    private func replaceContent<Content: View>(of window: NSWindow, title: String, rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        let containerController = makeFrostedContainerController(hostingController: hostingController)
        window.contentViewController = containerController
        window.title = title

        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize
        if size.width > 0, size.height > 0 {
            window.setContentSize(size)
        }

        ScreenManager.center(window)
    }

    private func makeFrostedContainerController<Content: View>(hostingController: NSHostingController<Content>) -> NSViewController {
        let effectView = NSVisualEffectView()
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        let containerController = NSViewController()
        containerController.view = effectView

        containerController.addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        return containerController
    }

    private func activateAndFocus(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        window = nil
        context = nil
    }
}

private struct FileRenameView: View {
    @State private var newName: String

    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    init(currentName: String, onCancel: @escaping () -> Void, onConfirm: @escaping (String) -> Void) {
        _newName = State(initialValue: currentName)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("folbox.rename.title"))
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 10) {
                Text(AppLocalization.string("folbox.rename.name"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .trailing)

                TextField(AppLocalization.string("folbox.rename.placeholder"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        onConfirm(newName)
                    }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(AppLocalization.string("folbox.common.cancel")) {
                    onCancel()
                }
                Button(AppLocalization.string("folbox.rename.confirm")) {
                    onConfirm(newName)
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
