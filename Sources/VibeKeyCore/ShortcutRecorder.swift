import CoreGraphics
import Foundation

public struct RecordedShortcut: Equatable, Sendable {
    public let keys: [String]

    public init(keys: [String]) {
        self.keys = keys
    }

    public var actionConfig: ActionConfig {
        .keySequence(keys: keys)
    }

    public var display: String {
        let symbols = [
            "⌃": "control", "⌥": "option", "⇧": "shift",
            "⌘": "command", "Fn": "fn"
        ]
        let modifiers = keys.dropLast().compactMap { key in
            symbols.first(where: { $0.value == key.lowercased() })?.key
        }
        return (modifiers + [Self.targetDisplay(keys.last ?? "")]).joined()
    }

    static func targetDisplay(_ name: String) -> String {
        switch name.lowercased() {
        case "return", "enter": return "⏎"
        case "delete", "backspace": return "⌫"
        case "forwarddelete": return "⌦"
        case "escape", "esc": return "⎋"
        case "tab": return "⇥"
        case "space": return "Space"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        case "fn": return "Fn"
        default: return name.uppercased()
        }
    }
}

public struct ShortcutRecordingBuffer: Sendable {
    private static let modifierOrder = ["control", "option", "shift", "command", "fn"]
    private(set) var modifiers: Set<String> = []

    public init() {}

    public var partialDisplay: String {
        Self.modifierOrder
            .filter { modifiers.contains($0) }
            .map { $0 == "fn" ? "Fn" : Self.modifierDisplay($0) }
            .joined()
    }

    private static func modifierDisplay(_ name: String) -> String {
        switch name {
        case "control": return "⌃"
        case "option": return "⌥"
        case "shift": return "⇧"
        case "command": return "⌘"
        default: return "Fn"
        }
    }

    public mutating func update(flags: CGEventFlags) {
        modifiers = Self.modifiers(from: flags)
    }

    @discardableResult
    public mutating func recordModifierChange(flags: CGEventFlags) -> RecordedShortcut? {
        let next = Self.modifiers(from: flags)
        if modifiers == ["fn"], next.isEmpty {
            modifiers = []
            return RecordedShortcut(keys: ["fn"])
        }
        modifiers = next
        return nil
    }

    @discardableResult
    public mutating func record(keyCode: CGKeyCode, flags: CGEventFlags) -> RecordedShortcut? {
        modifiers = Self.modifiers(from: flags)
        guard let target = VibeKeyKeyMap.name(for: keyCode) else { return nil }

        let keys = Self.modifierOrder.filter { modifiers.contains($0) } + [target]
        return RecordedShortcut(keys: keys)
    }

    public static func modifiers(from flags: CGEventFlags) -> Set<String> {
        var result: Set<String> = []
        if flags.contains(.maskControl) { result.insert("control") }
        if flags.contains(.maskAlternate) { result.insert("option") }
        if flags.contains(.maskShift) { result.insert("shift") }
        if flags.contains(.maskCommand) { result.insert("command") }
        if flags.contains(.maskSecondaryFn) { result.insert("fn") }
        return result
    }
}

extension VibeKeyKeyMap {
    public static func name(for virtualKey: CGKeyCode) -> String? {
        switch virtualKey {
        case 0x24: return "return"
        case 0x33: return "delete"
        case 0x75: return "forwarddelete"
        case 0x35: return "escape"
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x7E: return "up"
        case 0x7D: return "down"
        case 0x7B: return "left"
        case 0x7C: return "right"
        case 0x73: return "home"
        case 0x77: return "end"
        case 0x74: return "pageup"
        case 0x79: return "pagedown"
        case 0x3F: return "fn"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 0x00: return "a"
        case 0x0B: return "b"
        case 0x08: return "c"
        case 0x02: return "d"
        case 0x0E: return "e"
        case 0x03: return "f"
        case 0x05: return "g"
        case 0x04: return "h"
        case 0x22: return "i"
        case 0x26: return "j"
        case 0x28: return "k"
        case 0x25: return "l"
        case 0x2E: return "m"
        case 0x2D: return "n"
        case 0x1F: return "o"
        case 0x23: return "p"
        case 0x0C: return "q"
        case 0x0F: return "r"
        case 0x01: return "s"
        case 0x11: return "t"
        case 0x20: return "u"
        case 0x09: return "v"
        case 0x0D: return "w"
        case 0x07: return "x"
        case 0x10: return "y"
        case 0x06: return "z"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 42: return "\\"
        case 50: return "`"
        default: return nil
        }
    }
}
