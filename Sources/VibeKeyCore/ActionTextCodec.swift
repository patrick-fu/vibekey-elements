import CoreGraphics
import Foundation

public enum ActionConfigTextCodecError: Error, Equatable {
    case emptyAction
    case unknownKey(String)
    case missingTargetKey
}

public enum VibeKeyKeyMap {
    public static func virtualKey(for name: String) -> CGKeyCode? {
        switch name.lowercased() {
        case "return", "enter": return 0x24
        case "delete", "backspace": return 0x33
        case "forwarddelete": return 0x75
        case "escape", "esc": return 0x35
        case "tab": return 0x30
        case "space": return 0x31
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        case "fn": return 0x3F
        case "f1": return 122
        case "f2": return 120
        case "f3": return 99
        case "f4": return 118
        case "f5": return 96
        case "f6": return 97
        case "f7": return 98
        case "f8": return 100
        case "f9": return 101
        case "f10": return 109
        case "f11": return 103
        case "f12": return 111
        case "0": return 29
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        case "8": return 28
        case "9": return 25
        case "a": return 0x00
        case "b": return 0x0B
        case "c": return 0x08
        case "d": return 0x02
        case "e": return 0x0E
        case "f": return 0x03
        case "g": return 0x05
        case "h": return 0x04
        case "i": return 0x22
        case "j": return 0x26
        case "k": return 0x28
        case "l": return 0x25
        case "m": return 0x2E
        case "n": return 0x2D
        case "o": return 0x1F
        case "p": return 0x23
        case "q": return 0x0C
        case "r": return 0x0F
        case "s": return 0x01
        case "t": return 0x11
        case "u": return 0x20
        case "v": return 0x09
        case "w": return 0x0D
        case "x": return 0x07
        case "y": return 0x10
        case "z": return 0x06
        case "-", "_": return 27
        case "=", "+": return 24
        case "[", "{": return 33
        case "]", "}": return 30
        case ";", ":": return 41
        case "'", "\"": return 39
        case ",", "<": return 43
        case ".", ">": return 47
        case "/", "?": return 44
        case "\\", "|": return 42
        case "`", "~": return 50
        default: return nil


        }
    }
}
public enum ActionConfigTextCodec {
    public static func parse(_ raw: String) throws -> ActionConfig {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw ActionConfigTextCodecError.emptyAction }
        if text.hasPrefix("$") || text.lowercased().hasPrefix("sh ") {
            let command = text.hasPrefix("$") ? String(text.dropFirst()).trimmingCharacters(in: .whitespaces) : text
            return .shellCommand(command: command)
        }

        switch text.lowercased().replacingOccurrences(of: "_", with: "") {
        case "wheelup", "scrollup": return .mouseWheel(direction: .up)
        case "wheeldown", "scrolldown": return .mouseWheel(direction: .down)
        default: break
        }

        var modifiers: Set<String> = []
        var target: String?
        for token in text.split(whereSeparator: \.isWhitespace) {
            let key = token.lowercased()
            switch key {
            case "command", "cmd", "⌘": modifiers.insert("command")
            case "shift", "⇧": modifiers.insert("shift")
            case "option", "alt", "⌥": modifiers.insert("option")
            case "control", "ctrl", "⌃": modifiers.insert("control")
            case "fn": modifiers.insert("fn")
            default:
                guard target == nil else { throw ActionConfigTextCodecError.missingTargetKey }
                target = key
            }
        }

        if target == nil, modifiers == ["fn"] {
            target = "fn"
            modifiers.remove("fn")
        }

        guard let target else { throw ActionConfigTextCodecError.missingTargetKey }
        guard VibeKeyKeyMap.virtualKey(for: target) != nil else {
            throw ActionConfigTextCodecError.unknownKey(target)
        }

        let canonicalTarget = target == "backspace" ? "delete" : target
        let order = ["control", "option", "shift", "command", "fn"]
        let keys = order.filter(modifiers.contains) + [canonicalTarget]
        return .keySequence(keys: keys)
    }

    public static func encode(_ action: ActionConfig) -> String {
        switch action {
        case let .keySequence(keys):
            let symbol: [String: String] = [
                "command": "⌘", "shift": "⇧", "option": "⌥", "control": "⌃", "fn": "Fn"
            ]
            let modifiers = keys.dropLast().compactMap { symbol[$0.lowercased()] }
            let target = keys.last.map { $0.lowercased() == "fn" ? "Fn" : $0.uppercased() } ?? ""
            return (modifiers + [target]).joined(separator: " ")
        case let .mouseWheel(direction):
            return direction == .up ? "WheelUp" : "WheelDown"
        case let .shellCommand(command):
            return "$ \(command)"
        }
    }
}
