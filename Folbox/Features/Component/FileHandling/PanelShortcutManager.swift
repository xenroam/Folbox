import Combine
import CoreGraphics

@MainActor
final class PanelShortcutManager: ObservableObject {
    static let shared = PanelShortcutManager()

    @Published private(set) var isRecording = false

    private let hotKeyManager = HotKeyManager.shared

    private init() {
        refreshRegistration()
    }

    var shortcutDisplay: String {
        let keyCode = CGKeyCode(SettingsStore.shared.panelShortcutKeyCode)
        let flags = HotKeyManager.normalizedFlags(rawValue: SettingsStore.shared.panelShortcutModifierFlagsRaw)
        return Keyboard.shortNameShortcut(keyCode: keyCode, flags: flags)
    }

    func beginRecording(onCaptured: @escaping () -> Void) {
        stopRecording()
        isRecording = true

        hotKeyManager.startRecording(
            onCaptured: { [weak self] keyCode, modifiers in
                SettingsStore.shared.panelShortcutKeyCode = Int(keyCode)
                SettingsStore.shared.panelShortcutModifierFlagsRaw = modifiers.rawValue
                self?.isRecording = false
                onCaptured()
            },
            onCancelled: { [weak self] in
                self?.isRecording = false
            }
        )
    }

    func clearShortcut(onCleared: (() -> Void)? = nil) {
        stopRecording()
        SettingsStore.shared.panelShortcutKeyCode = Int(CGKeyCode.disabled)
        SettingsStore.shared.panelShortcutModifierFlagsRaw = CGEventFlags.disabled.rawValue
        refreshRegistration()
        onCleared?()
    }

    func stopRecording() {
        hotKeyManager.stopRecording()
        isRecording = false
    }

    func refreshRegistration() {
        let shortcut = HotKeyManager.Shortcut(
            keyCode: CGKeyCode(SettingsStore.shared.panelShortcutKeyCode),
            modifiers: HotKeyManager.normalizedFlags(rawValue: SettingsStore.shared.panelShortcutModifierFlagsRaw)
        )

        hotKeyManager.register(shortcut: shortcut) {
            DesktopPanelController.shared.togglePanelsToForegroundMode()
        }
    }
}
