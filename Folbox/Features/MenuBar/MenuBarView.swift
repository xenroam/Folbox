import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject private var appSettings: SettingsStore
    @EnvironmentObject private var instanceStore: ComponentStore
    @EnvironmentObject private var desktopAutoMoveStore: DesktopAutoMoveStore

    private func dismissMenuWindow() {
        NSApp.sendAction(#selector(NSMenu.cancelTracking), to: nil, from: nil)
        if let window = NSApp.keyWindow {
            window.orderOut(nil)
            window.close()
        }
    }

    private func showAboutWindow() {
        dismissMenuWindow()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            AboutWin.shared.show()
        }
    }

    private func checkForUpdates() {
        dismissMenuWindow()
        DispatchQueue.main.async {
            UpdateManager.shared.checkForUpdates()
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(AppDefaults.AppInfo.projectName())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Button {
                    dismissMenuWindow()
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        ComponentConfigurationWin.shared.showCreate(instanceStore: instanceStore)
                    }
                } label: {
                    Label(appSettings.t("folbox.menu.create_component"), systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.8))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 1)
                        )
                        .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }

            SettingsView()
                .environmentObject(appSettings)
                .environmentObject(instanceStore)
                .environmentObject(desktopAutoMoveStore)

            HStack(spacing: 10) {
                Menu {
                    Button(appSettings.t("folbox.menu.check_updates")) {
                        checkForUpdates()
                    }

                    Button(appSettings.t("folbox.menu.about")) {
                        showAboutWindow()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(Text(appSettings.t("folbox.menu.more")))

                Spacer(minLength: 0)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}
