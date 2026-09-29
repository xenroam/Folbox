import CoreGraphics

extension CGKeyCode {
    static let disabled: CGKeyCode = 0xFFFF

    var isDisabled: Bool {
        self == Self.disabled
    }
}

extension CGEventFlags {
    static let disabled: CGEventFlags = CGEventFlags(rawValue: 0)

    var isDisabled: Bool {
        rawValue == 0
    }
}

enum Keyboard {
    static func shortNameShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
        if keyCode.isDisabled {
            return AppLocalization.string("folbox.common.not_set")
        }

        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append(AppLocalization.string("folbox.keyboard.modifier.command")) }
        if flags.contains(.maskControl) { parts.append(AppLocalization.string("folbox.keyboard.modifier.control")) }
        if flags.contains(.maskAlternate) { parts.append(AppLocalization.string("folbox.keyboard.modifier.option")) }
        if flags.contains(.maskShift) { parts.append(AppLocalization.string("folbox.keyboard.modifier.shift")) }
        parts.append(keyCodeToFullName(keyCode))
        return parts.joined(separator: " + ")
    }

    static func keyCodeToFullName(_ keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return AppLocalization.string("folbox.keyboard.tab")
        case 49: return AppLocalization.string("folbox.keyboard.space")
        case 50: return "`"
        case 51: return AppLocalization.string("folbox.keyboard.delete")
        case 53: return AppLocalization.string("folbox.keyboard.escape")
        case 65: return AppLocalization.string("folbox.keyboard.decimal")
        case 67: return AppLocalization.string("folbox.keyboard.multiply")
        case 69: return AppLocalization.string("folbox.keyboard.plus")
        case 71: return AppLocalization.string("folbox.keyboard.clear")
        case 75: return AppLocalization.string("folbox.keyboard.divide")
        case 76: return AppLocalization.string("folbox.keyboard.enter")
        case 78: return AppLocalization.string("folbox.keyboard.minus")
        case 81: return AppLocalization.string("folbox.keyboard.equals")
        case 82: return AppLocalization.string("folbox.keyboard.numpad", "0")
        case 83: return AppLocalization.string("folbox.keyboard.numpad", "1")
        case 84: return AppLocalization.string("folbox.keyboard.numpad", "2")
        case 85: return AppLocalization.string("folbox.keyboard.numpad", "3")
        case 86: return AppLocalization.string("folbox.keyboard.numpad", "4")
        case 87: return AppLocalization.string("folbox.keyboard.numpad", "5")
        case 88: return AppLocalization.string("folbox.keyboard.numpad", "6")
        case 89: return AppLocalization.string("folbox.keyboard.numpad", "7")
        case 91: return AppLocalization.string("folbox.keyboard.numpad", "8")
        case 92: return AppLocalization.string("folbox.keyboard.numpad", "9")
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 114: return AppLocalization.string("folbox.keyboard.help")
        case 115: return AppLocalization.string("folbox.keyboard.home")
        case 116: return AppLocalization.string("folbox.keyboard.page_up")
        case 117: return AppLocalization.string("folbox.keyboard.forward_delete")
        case 118: return "F4"
        case 119: return AppLocalization.string("folbox.keyboard.end")
        case 120: return "F2"
        case 121: return AppLocalization.string("folbox.keyboard.page_down")
        case 122: return "F1"
        case 123: return AppLocalization.string("folbox.keyboard.left_arrow")
        case 124: return AppLocalization.string("folbox.keyboard.right_arrow")
        case 125: return AppLocalization.string("folbox.keyboard.down_arrow")
        case 126: return AppLocalization.string("folbox.keyboard.up_arrow")
        case 144: return AppLocalization.string("folbox.keyboard.clear")
        default: return AppLocalization.string("folbox.keyboard.key_code", String(keyCode))
        }
    }
}
