import SwiftUI
import AppKit

@MainActor
final class AboutWin: NSObject, NSWindowDelegate {
    static let shared = AboutWin()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if let window {
            ScreenManager.center(window)
            applyPreferredContentSize()
            activateAndFocus(window)
            return
        }

        let view = AboutView(onPreferredSizeChange: { [weak self] _ in
            self?.applyPreferredContentSize()
        })
        .environmentObject(SettingsStore.shared)
        let title = AppLocalization.string("folbox.window.about", AppDefaults.AppInfo.projectName())
        window = makeWindow(title: title, rootView: view)
    }

    private func makeWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let containerController = makeFrostedContainerController(hostingController: hostingController)

        let window = NSWindow(contentViewController: containerController)
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

    private func applyPreferredContentSize() {
        guard let window else { return }

        let measured = measuredPreferredSize(for: window)
        let target = NSSize(
            width: max(0, ceil(measured.width)),
            height: max(0, ceil(measured.height))
        )

        if abs(window.contentLayoutRect.width - target.width) < 0.5,
           abs(window.contentLayoutRect.height - target.height) < 0.5 {
            return
        }

        window.setContentSize(target)
    }

    private func measuredPreferredSize(for window: NSWindow) -> NSSize {
        if let contentController = window.contentViewController {
            contentController.view.layoutSubtreeIfNeeded()

            if let hostedView = contentController.children.first?.view {
                hostedView.layoutSubtreeIfNeeded()
                let hostedSize = hostedView.fittingSize
                if hostedSize.width > 0, hostedSize.height > 0 {
                    return hostedSize
                }
            }

            let contentSize = contentController.view.fittingSize
            if contentSize.width > 0, contentSize.height > 0 {
                return contentSize
            }
        }

        return window.contentLayoutRect.size
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        window = nil
    }
}
