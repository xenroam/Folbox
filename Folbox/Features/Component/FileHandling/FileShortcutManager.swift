import Combine
import CoreGraphics
import Foundation

@MainActor
final class FileShortcutManager: ObservableObject {
    struct Target: Equatable {
        let instanceID: UUID
        let filePath: String
    }

    static let shared = FileShortcutManager()

    @Published private(set) var recordingTarget: Target?

    private let hotKeyManager = HotKeyManager.shared
    private let instanceStore = ComponentStore.shared
    private var registeredTokens: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        instanceStore.$instances
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshRegistrations()
            }
            .store(in: &cancellables)

        refreshRegistrations()
    }

    var isRecording: Bool {
        recordingTarget != nil
    }

    func isRecording(instanceID: UUID, filePath: String) -> Bool {
        recordingTarget == Target(instanceID: instanceID, filePath: filePath)
    }

    func hasConfiguredShortcut(instanceID: UUID, filePath: String) -> Bool {
        instanceStore.hasConfiguredFileShortcut(instanceID: instanceID, filePath: filePath)
    }

    func shortcutDisplay(instanceID: UUID, filePath: String) -> String {
        guard let shortcut = instanceStore.fileShortcut(instanceID: instanceID, filePath: filePath),
              shortcut.isConfigured else {
                        return AppLocalization.string("folbox.common.not_set")
        }

        return Keyboard.shortNameShortcut(
            keyCode: CGKeyCode(shortcut.keyCode),
            flags: HotKeyManager.normalizedFlags(rawValue: shortcut.modifierFlagsRaw)
        )
    }

    func beginRecording(instanceID: UUID, filePath: String, onCaptured: (() -> Void)? = nil, onCancelled: (() -> Void)? = nil) {
        stopRecording()

        let target = Target(instanceID: instanceID, filePath: filePath)
        recordingTarget = target

        hotKeyManager.startRecording(
            onCaptured: { [weak self] keyCode, modifiers in
                guard let self else { return }
                guard self.recordingTarget == target else { return }

                self.instanceStore.clearMatchingFileShortcut(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    excludingInstanceID: instanceID,
                    excludingFilePath: filePath
                )
                self.instanceStore.setFileShortcut(
                    instanceID: instanceID,
                    filePath: filePath,
                    keyCode: keyCode,
                    modifiers: modifiers
                )
                self.recordingTarget = nil
                onCaptured?()
            },
            onCancelled: { [weak self] in
                guard let self else { return }
                if self.recordingTarget == target {
                    self.recordingTarget = nil
                }
                onCancelled?()
            }
        )
    }

    func clearShortcut(instanceID: UUID, filePath: String, onCleared: (() -> Void)? = nil) {
        if recordingTarget == Target(instanceID: instanceID, filePath: filePath) {
            stopRecording()
        }
        instanceStore.clearFileShortcut(instanceID: instanceID, filePath: filePath)
        objectWillChange.send()
        onCleared?()
    }

    func stopRecording() {
        hotKeyManager.stopRecording()
        recordingTarget = nil
    }

    func refreshRegistrations() {
        for token in registeredTokens {
            hotKeyManager.unregister(token: token)
        }
        registeredTokens.removeAll()

        var seenSignatures: Set<String> = []

        let sortedInstances = instanceStore.instances.sorted {
            $0.id.uuidString < $1.id.uuidString
        }

        for instance in sortedInstances {
            for filePath in instance.filePaths {
                guard let shortcut = instance.fileShortcutsByPath[filePath], shortcut.isConfigured else {
                    continue
                }

                let normalizedFlags = HotKeyManager.normalizedFlags(rawValue: shortcut.modifierFlagsRaw).rawValue
                let signature = "\(shortcut.keyCode)-\(normalizedFlags)"
                guard seenSignatures.insert(signature).inserted else {
                    continue
                }

                let target = Target(instanceID: instance.id, filePath: filePath)
                let token = registrationToken(for: target)
                let registrationShortcut = HotKeyManager.Shortcut(
                    keyCode: CGKeyCode(shortcut.keyCode),
                    modifiers: HotKeyManager.normalizedFlags(rawValue: shortcut.modifierFlagsRaw)
                )

                let didRegister = hotKeyManager.register(shortcut: registrationShortcut, token: token) { [weak self] in
                    self?.openFile(for: target)
                }

                if didRegister {
                    registeredTokens.insert(token)
                }
            }
        }
    }

    private func openFile(for target: Target) {
        if instanceStore.openFile(instanceID: target.instanceID, filePath: target.filePath) {
            DesktopPanelController.shared.applyDefocusBehavior()
        }
    }

    private func registrationToken(for target: Target) -> String {
        "file-shortcut:\(target.instanceID.uuidString):\(target.filePath)"
    }
}
