import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class HotKeyManager {
    struct Shortcut {
        let keyCode: CGKeyCode
        let modifiers: CGEventFlags

        var isConfigured: Bool {
            !keyCode.isDisabled && !modifiers.isDisabled
        }
    }

    private struct RegisteredHotKey {
        let id: UInt32
        let ref: EventHotKeyRef
    }

    static let shared = HotKeyManager()

    private var hotKeyHandlerRef: EventHandlerRef?
    private var recordingMonitor: Any?
    private var registeredHotKeysByToken: [String: RegisteredHotKey] = [:]
    private var handlersByID: [UInt32: () -> Void] = [:]
    private var nextHotKeyID: UInt32 = 1

    private static let hotKeySignature: OSType = 0x4642484B
    private static let defaultToken = "default-hotkey"

    private init() {}

    var isRecording: Bool {
        recordingMonitor != nil
    }

    func register(shortcut: Shortcut, onTriggered: @escaping () -> Void) {
        _ = register(shortcut: shortcut, token: Self.defaultToken, onTriggered: onTriggered)
    }

    @discardableResult
    func register(shortcut: Shortcut, token: String, onTriggered: @escaping () -> Void) -> Bool {
        unregister(token: token)
        guard shortcut.isConfigured else { return false }

        installHotKeyHandlerIfNeeded()

        let hotKeyIDValue = nextAvailableHotKeyID()
        guard hotKeyIDValue != 0 else {
            return false
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyIDValue)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else { return false }

        registeredHotKeysByToken[token] = RegisteredHotKey(id: hotKeyIDValue, ref: hotKeyRef)
        handlersByID[hotKeyIDValue] = onTriggered
        return true
    }

    func unregister() {
        unregister(token: Self.defaultToken)
    }

    func unregister(token: String) {
        guard let registration = registeredHotKeysByToken.removeValue(forKey: token) else {
            return
        }

        UnregisterEventHotKey(registration.ref)
        handlersByID.removeValue(forKey: registration.id)
    }

    func startRecording(onCaptured: @escaping (CGKeyCode, CGEventFlags) -> Void, onCancelled: (() -> Void)? = nil) {
        stopRecording()

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.stopRecording()
                onCancelled?()
                return nil
            }

            let modifiers = Self.normalizedFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            guard !modifiers.isDisabled else {
                return nil
            }

            onCaptured(CGKeyCode(event.keyCode), modifiers)
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
    }

    static func normalizedFlags(rawValue: UInt64) -> CGEventFlags {
        CGEventFlags(rawValue: rawValue)
            .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            userData,
            &hotKeyHandlerRef
        )

        if status != noErr {
            hotKeyHandlerRef = nil
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return noErr }
        guard hotKeyID.signature == Self.hotKeySignature else { return noErr }

        handlersByID[hotKeyID.id]?()
        return noErr
    }

    private func nextAvailableHotKeyID() -> UInt32 {
        var candidate = nextHotKeyID
        if candidate == 0 {
            candidate = 1
        }

        let start = candidate
        while handlersByID[candidate] != nil {
            candidate = candidate == UInt32.max ? 1 : candidate + 1
            if candidate == start {
                return 0
            }
        }

        nextHotKeyID = candidate == UInt32.max ? 1 : candidate + 1
        return candidate
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
        if flags.contains(.maskControl) { result |= UInt32(controlKey) }
        if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
        if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
        return result
    }
}
