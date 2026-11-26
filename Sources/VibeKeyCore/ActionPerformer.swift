import Foundation
import CoreGraphics
import ApplicationServices

public enum ActionPerformer {
    private static let actionQueue = DispatchQueue(label: "com.patrickfu.vibekey.action", qos: .userInteractive)

    public static func hasAccessibilityPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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

    /// True when the action is a single key that can be held down for the
    /// duration of a physical long press instead of tapped. Modifier keys are
    /// held via synthetic flagsChanged events (verified to latch system state).
    /// "fn" is held the same way, but the event must be re-posted periodically:
    /// macOS does not latch synthetic .maskSecondaryFn into source state, while
    /// apps listening through event taps (e.g. voice-input triggers) see it.
    public static func supportsHold(_ action: ActionConfig) -> Bool {
        guard case let .keySequence(keys) = action else { return false }
        let normalized = keys.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard normalized.count == 1, let key = normalized.first else { return false }
        return key == "fn" || modifierFlag(for: key) != nil || keyCode(for: key) != nil
    }

    /// Press and hold the action's key. Pair with `endHold` on physical key-up.
    /// No-op for actions that do not support hold.
    public static func beginHold(_ action: ActionConfig) {
        guard supportsHold(action),
              case let .keySequence(keys) = action,
              let key = keys.first?.lowercased().trimmingCharacters(in: .whitespaces) else { return }
        actionQueue.async {
            postKey(key: key, keyDown: true)
            if key == "fn" {
                startFnHoldRefreshLoop()
            }
        }
    }

    /// Release a key previously held via `beginHold`.
    public static func endHold(_ action: ActionConfig) {
        guard supportsHold(action),
              case let .keySequence(keys) = action,
              let key = keys.first?.lowercased().trimmingCharacters(in: .whitespaces) else { return }
        actionQueue.async {
            if key == "fn" {
                stopFnHoldRefreshLoop()
            }
            postKey(key: key, keyDown: false)
        }
    }

    /// While fn is held, re-post its flagsChanged event ~10x per second so
    /// event-tap listeners keep observing a held state.
    private static var fnHoldTimer: DispatchSourceTimer?

    private static func startFnHoldRefreshLoop() {
        stopFnHoldRefreshLoop()
        let timer = DispatchSource.makeTimerSource(queue: actionQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { postFnFlagsChanged(keyDown: true) }
        timer.resume()
        fnHoldTimer = timer
    }

    private static func stopFnHoldRefreshLoop() {
        fnHoldTimer?.cancel()
        fnHoldTimer = nil
    }

    private static func postFnFlagsChanged(keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x3F, keyDown: keyDown) else { return }
        event.type = .flagsChanged
        event.flags = keyDown ? [.maskSecondaryFn] : []
        event.post(tap: .cghidEventTap)
    }

    private static func modifierFlag(for key: String) -> CGEventFlags? {
        switch key {
        case "command", "cmd", "⌘": return .maskCommand
        case "shift", "⇧": return .maskShift
        case "option", "alt", "⌥": return .maskAlternate
        case "control", "ctrl", "⌃": return .maskControl
        default: return nil
        }
    }

    /// Post a single key-down or key-up event. Runs on the action queue only.
    private static func postKey(key: String, keyDown: Bool) {
        if key == "fn" {
            postFnFlagsChanged(keyDown: keyDown)
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        // Modifiers latch system state through flagsChanged events; plain
        // keyDown events with modifier flags do not register as held.
        if let flag = modifierFlag(for: key) {
            guard let virtualKey = modifierVirtualKey(for: key),
                  let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { return }
            event.type = .flagsChanged
            event.flags = keyDown ? [flag] : []
            event.post(tap: .cghidEventTap)
            return
        }
        guard let code = keyCode(for: key),
              let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func modifierVirtualKey(for key: String) -> CGKeyCode? {
        switch key {
        case "command", "cmd", "⌘": return 0x37 // kVK_Command
        case "shift", "⇧": return 0x38 // kVK_Shift
        case "option", "alt", "⌥": return 0x3A // kVK_Option
        case "control", "ctrl", "⌃": return 0x3B // kVK_Control
        default: return nil
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
