import SwiftUI
import AppKit

@MainActor
final class FileShortcutSettingsWin: NSObject, NSWindowDelegate {
    static let shared = FileShortcutSettingsWin()

    private var windowsByTarget: [String: NSWindow] = [:]

    private override init() {
        super.init()
    }

    func show(instanceID: UUID, filePath: String, instanceStore: ComponentStore) {
        let key = windowKey(instanceID: instanceID, filePath: filePath)

        if let window = windowsByTarget[key] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = FileShortcutSettingsWinView(instanceID: instanceID, filePath: filePath)
        .environmentObject(instanceStore)

        let title = AppLocalization.string("folbox.file_shortcut.window_title", displayName(for: filePath))
        let window = makeWindow(title: title, rootView: view)
        windowsByTarget[key] = window
    }

    func close(instanceID: UUID, filePath: String) {
        let key = windowKey(instanceID: instanceID, filePath: filePath)
        windowsByTarget[key]?.close()
        windowsByTarget[key] = nil
    }

    private func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let containerController = makeFrostedContainerController(hostingController: hostingController)

        let window = EscapeClosableWindow(contentViewController: containerController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.delegate = self

        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize
        if size.width > 0, size.height > 0 {
            window.setContentSize(size)
        }

        ScreenManager.center(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        return window
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

    private func windowKey(instanceID: UUID, filePath: String) -> String {
        "\(instanceID.uuidString)::\(filePath)"
    }

    private func displayName(for filePath: String) -> String {
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        if name.lowercased().hasSuffix(".app") {
            return String(name.dropLast(4))
        }
        return name
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if let target = windowsByTarget.first(where: { $0.value === closedWindow })?.key {
            windowsByTarget[target] = nil
        }
    }
}

struct FileShortcutSettingsWinView: View {
    @StateObject private var shortcutManager = FileShortcutManager.shared

    let instanceID: UUID
    let filePath: String

    private var shortcutDisplay: String {
        shortcutManager.shortcutDisplay(instanceID: instanceID, filePath: filePath)
    }

    private var isRecording: Bool {
        shortcutManager.isRecording(instanceID: instanceID, filePath: filePath)
    }

    private var hasConfiguredShortcut: Bool {
        shortcutManager.hasConfiguredShortcut(instanceID: instanceID, filePath: filePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(AppLocalization.string("folbox.settings.shortcut"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 12)

                    if hasConfiguredShortcut {
                        Button(AppLocalization.string("folbox.common.clear")) {
                            shortcutManager.clearShortcut(instanceID: instanceID, filePath: filePath)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        if isRecording {
                            shortcutManager.stopRecording()
                        } else {
                            shortcutManager.beginRecording(instanceID: instanceID, filePath: filePath)
                        }
                    } label: {
                        Text(isRecording ? AppLocalization.string("folbox.settings.press_shortcut") : shortcutDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if isRecording {
                Text(AppLocalization.string("folbox.file_shortcut.press_escape"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .frame(width: 360)
        .onDisappear {
            if isRecording {
                shortcutManager.stopRecording()
            }
        }
    }
}
