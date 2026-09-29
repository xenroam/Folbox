import SwiftUI
import AppKit

private struct FileInfoSnapshot {
    let name: String
    let type: String
    let size: String
    let created: String
    let modified: String
    let path: String
}

@MainActor
final class FileInfoWin: NSObject, NSWindowDelegate {
    static let shared = FileInfoWin()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(fileURL: URL) {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let snapshot = snapshot(for: fileURL)
        let view = FileInfoView(snapshot: snapshot) { [weak self] in
            self?.close()
        }

        if let window {
            replaceContent(of: window, title: snapshot.name, rootView: view)
            activateAndFocus(window)
            return
        }

        self.window = makeWindow(title: snapshot.name, rootView: view)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func snapshot(for fileURL: URL) -> FileInfoSnapshot {
        let values = try? fileURL.resourceValues(forKeys: [
            .localizedTypeDescriptionKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isDirectoryKey
        ])

        let byteFormatter = ByteCountFormatter()
        byteFormatter.countStyle = .file

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let type = values?.localizedTypeDescription
            ?? ((values?.isDirectory == true)
                ? AppLocalization.string("folbox.file_info.folder")
                : AppLocalization.string("folbox.file_info.file"))
        let size = values?.fileSize.map { byteFormatter.string(fromByteCount: Int64($0)) } ?? "-"
        let created = values?.creationDate.map { dateFormatter.string(from: $0) } ?? "-"
        let modified = values?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "-"

        return FileInfoSnapshot(
            name: fileURL.lastPathComponent,
            type: type,
            size: size,
            created: created,
            modified: modified,
            path: fileURL.path
        )
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
    }
}

private struct FileInfoView: View {
    let snapshot: FileInfoSnapshot
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snapshot.name)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            VStack(spacing: 8) {
                infoRow(label: AppLocalization.string("folbox.file_info.type"), value: snapshot.type)
                infoRow(label: AppLocalization.string("folbox.file_info.size"), value: snapshot.size)
                infoRow(label: AppLocalization.string("folbox.file_info.created"), value: snapshot.created)
                infoRow(label: AppLocalization.string("folbox.file_info.modified"), value: snapshot.modified)
                infoRow(label: AppLocalization.string("folbox.file_info.path"), value: snapshot.path, multiline: true)
            }
            .textSelection(.enabled)

            HStack {
                Spacer(minLength: 0)
                Button(AppLocalization.string("folbox.common.close")) {
                    onClose()
                }
            }
        }
        .padding(16)
        .frame(width: 560)
    }

    @ViewBuilder
    private func infoRow(label: String, value: String, multiline: Bool = false) -> some View {
        HStack(alignment: multiline ? .top : .center, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)

            Text(value)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(multiline ? 3 : 1)
                .truncationMode(multiline ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
