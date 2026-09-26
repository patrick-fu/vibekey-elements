import Foundation
import CoreGraphics
import ApplicationServices

public enum ActionPerformer {
    private static let actionQueue = DispatchQueue(label: "com.patrickfu.vibekey.action", qos: .userInteractive)

    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public static func perform(_ action: ActionConfig) {
        actionQueue.async {
            switch action {
            case let .keySequence(keys):
                performKeySequence(keys)
            case let .mouseWheel(direction):
                performMouseWheel(direction)
            case let .shellCommand(command):
                performShellCommand(command)
            }
        }
    }

    public static func performMouseWheel(_ direction: MouseWheelDirection) {
        let delta: Int32 = direction == .up ? 5 : -5
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    public static func performShellCommand(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        try? process.run()
    }

    public static func performKeySequence(_ keys: [String]) {
        let normalized = keys.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Check for special single key "fn"
        if normalized.count == 1 && normalized.first == "fn" {
            postFnKeyToggle()
            return
        }

        var flags = CGEventFlags()
        var targetKeyCode: CGKeyCode?

        for key in normalized {
            switch key {
            case "command", "cmd", "⌘":
                flags.insert(.maskCommand)
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "option", "alt", "⌥":
                flags.insert(.maskAlternate)
            case "control", "ctrl", "⌃":
                flags.insert(.maskControl)
            case "fn":
                flags.insert(.maskSecondaryFn)
            default:
                if let code = keyCode(for: key) {
                    targetKeyCode = code
                }
            }
        }

        guard let code = targetKeyCode else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        usleep(15_000) // Safe 15ms delay inside background actionQueue
        keyUp.post(tap: .cghidEventTap)
    }

    private static func postFnKeyToggle() {
        let source = CGEventSource(stateID: .hidSystemState)
        let fnCode: CGKeyCode = 0x3F // kVK_Function
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: fnCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: fnCode, keyDown: false) else {
            return
        }
        down.flags = .maskSecondaryFn
        up.flags = []
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    private static func keyCode(for name: String) -> CGKeyCode? {
        switch name {
        case "return", "enter": return 0x24
        case "delete", "backspace": return 0x33
        case "escape", "esc": return 0x35
        case "tab": return 0x30
        case "space": return 0x31
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
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
        default: return nil
        }
    }
}
