import Carbon
import Foundation

enum HotkeyError: LocalizedError {
    case eventHandlerInstallFailed
    case registrationFailed

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallFailed:
            return "Failed to install global shortcut event handler."
        case .registrationFailed:
            return "Failed to register global shortcut."
        }
    }
}

private let hotkeySignature: OSType = 0x51425831 // QBX1
private let hotkeyIdentifier: UInt32 = 1

private func hotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(noErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.trigger()
    return OSStatus(noErr)
}

final class HotkeyManager {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ combo: HotKeyCombo) throws {
        try ensureEventHandlerInstalled()
        unregister()

        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: hotkeyIdentifier)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw HotkeyError.registrationFailed
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func ensureEventHandlerInstalled() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw HotkeyError.eventHandlerInstallFailed
        }
    }

    fileprivate func trigger() {
        onHotKey?()
    }
}
