import Carbon
import AppKit
import Foundation

struct HotKeyCombo: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    var normalizedString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("option") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("command") }
        parts.append(Self.displayKey(for: keyCode))
        return parts.joined(separator: "+")
    }

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.prettyKey(for: keyCode))
        return parts.joined()
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else {
            return nil
        }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = modifiers
    }

    static func parse(_ rawValue: String) -> HotKeyCombo? {
        let tokens = rawValue
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let keyToken = tokens.last,
              let keyCode = keyCode(for: keyToken)
        else {
            return nil
        }

        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "control", "ctrl", "⌃":
                modifiers |= UInt32(controlKey)
            case "option", "opt", "alt", "⌥":
                modifiers |= UInt32(optionKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            case "command", "cmd", "⌘":
                modifiers |= UInt32(cmdKey)
            default:
                return nil
            }
        }

        guard modifiers != 0 else {
            return nil
        }

        return HotKeyCombo(keyCode: keyCode, carbonModifiers: modifiers)
    }

    private static func keyCode(for token: String) -> UInt32? {
        if token.count == 1, let char = token.first {
            if let code = letterKeyCodes[char] {
                return code
            }
            if let code = digitKeyCodes[char] {
                return code
            }
        }

        switch token {
        case "space":
            return UInt32(kVK_Space)
        case "return", "enter":
            return UInt32(kVK_Return)
        case "tab":
            return UInt32(kVK_Tab)
        case "escape", "esc":
            return UInt32(kVK_Escape)
        default:
            return nil
        }
    }

    private static func displayKey(for keyCode: UInt32) -> String {
        if let letter = letterKeyCodes.first(where: { $0.value == keyCode })?.key {
            return String(letter)
        }

        if let number = digitKeyCodes.first(where: { $0.value == keyCode })?.key {
            return String(number)
        }

        switch keyCode {
        case UInt32(kVK_Space):
            return "space"
        case UInt32(kVK_Return):
            return "return"
        case UInt32(kVK_Tab):
            return "tab"
        case UInt32(kVK_Escape):
            return "escape"
        default:
            return "unknown"
        }
    }

    private static func prettyKey(for keyCode: UInt32) -> String {
        if let letter = letterKeyCodes.first(where: { $0.value == keyCode })?.key {
            return String(letter).uppercased()
        }
        if let number = digitKeyCodes.first(where: { $0.value == keyCode })?.key {
            return String(number)
        }

        switch keyCode {
        case UInt32(kVK_Space):
            return "Space"
        case UInt32(kVK_Return):
            return "Return"
        case UInt32(kVK_Tab):
            return "Tab"
        case UInt32(kVK_Escape):
            return "Esc"
        default:
            return "Key\(keyCode)"
        }
    }

    private static let letterKeyCodes: [Character: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46
    ]

    private static let digitKeyCodes: [Character: UInt32] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29
    ]
}
