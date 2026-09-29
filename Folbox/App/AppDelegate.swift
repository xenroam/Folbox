import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DesktopPanelController.shared.restorePanels()
        _ = PanelShortcutManager.shared
        _ = FileShortcutManager.shared
    }
}
