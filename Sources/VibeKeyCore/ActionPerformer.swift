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
        VibeKeyKeyMap.virtualKey(for: name)
    }
}
