import SwiftUI
import AppKit

@main
struct Folbox: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appSettings = SettingsStore.shared
    @StateObject private var instanceStore = ComponentStore.shared
    @StateObject private var desktopAutoMoveStore = DesktopAutoMoveStore.shared

    private func statusBarIconImage(named name: String) -> NSImage {
        let targetSize = NSSize(width: 18, height: 18)
        guard let image = NSImage(named: name) else {
            return NSImage(size: targetSize)
        }

        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        resizedImage.unlockFocus()
        resizedImage.isTemplate = true
        return resizedImage
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appSettings)
                .environmentObject(instanceStore)
                .environmentObject(desktopAutoMoveStore)
        } label: {
            Image(nsImage: statusBarIconImage(named: "StatusBarIcon"))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .accessibilityLabel(AppDefaults.AppInfo.projectName())
        }
        .menuBarExtraStyle(.window)
    }
}
