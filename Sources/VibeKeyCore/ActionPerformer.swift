import Foundation
import CoreGraphics
import ApplicationServices

public enum ActionPerformer {
    /// Canonical virtual-key identity shared by hold and tap paths so aliases
    /// (e.g. "return" / "enter", "cmd" / "⌘") share one reference count.
    enum HoldKey: Hashable, Sendable {
        case fn
        case modifier(CGKeyCode)
        case regular(CGKeyCode)
    }

    private static let actionQueue = DispatchQueue(label: "com.patrickfu.vibekey.action", qos: .userInteractive)

    /// Reference counts of currently held virtual keys. Accessed only on `actionQueue`.
    private static var heldKeyCounts: [HoldKey: Int] = [:]

    /// While fn is held, re-post its flagsChanged event ~10x per second so
    /// event-tap listeners keep observing a held state. Accessed only on `actionQueue`.
    private static var fnHoldTimer: DispatchSourceTimer?

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
        canonicalHoldKey(for: action) != nil
    }

    /// Press and hold the action's key. Pair with `endHold` on physical key-up.
    /// No-op for actions that do not support hold.
    public static func beginHold(_ action: ActionConfig) {
        guard let holdKey = canonicalHoldKey(for: action) else { return }
        actionQueue.async {
            let count = heldKeyCounts[holdKey, default: 0]
            heldKeyCounts[holdKey] = count + 1
            guard count == 0 else { return }
            postHoldKey(holdKey, keyDown: true)
            if holdKey == .fn {
                startFnHoldRefreshLoop()
            }
        }
    }

    /// Release a key previously held via `beginHold`.
    public static func endHold(_ action: ActionConfig) {
        guard let holdKey = canonicalHoldKey(for: action) else { return }
        actionQueue.async {
            releaseHoldLocked(holdKey)
        }
    }

    /// Releases every synthetic key currently held via `beginHold` and stops
    /// any active `fn` refresh loop. Use `synchronous: true` during app
    /// termination so release events are posted before the process exits.
    public static func releaseAllHolds(synchronous: Bool = false) {
        let work = {
            let activeKeys = Array(heldKeyCounts.keys)
            heldKeyCounts.removeAll()
            stopFnHoldRefreshLoop()
            for holdKey in activeKeys {
                postHoldKey(holdKey, keyDown: false)
            }
        }
        if synchronous {
            actionQueue.sync(execute: work)
        } else {
            actionQueue.async(execute: work)
        }
    }

    static func canonicalHoldKey(for action: ActionConfig) -> HoldKey? {
        guard case let .keySequence(keys) = action else { return nil }
        let normalized = keys.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard normalized.count == 1, let key = normalized.first, !key.isEmpty else { return nil }
        if key == "fn" { return .fn }
        if let virtualKey = modifierVirtualKey(for: key) { return .modifier(virtualKey) }
        if let code = keyCode(for: key) { return .regular(code) }
        return nil
    }

    private static func releaseHoldLocked(_ holdKey: HoldKey) {
        guard let count = heldKeyCounts[holdKey], count > 0 else { return }
        if count > 1 {
            heldKeyCounts[holdKey] = count - 1
            return
        }
        heldKeyCounts.removeValue(forKey: holdKey)
        if holdKey == .fn {
            stopFnHoldRefreshLoop()
        }
        postHoldKey(holdKey, keyDown: false)
    }

    private static func startFnHoldRefreshLoop() {
        stopFnHoldRefreshLoop()
        let timer = DispatchSource.makeTimerSource(queue: actionQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler {
            guard heldKeyCounts[.fn, default: 0] > 0 else {
                stopFnHoldRefreshLoop()
                return
            }
            postFnFlagsChanged(keyDown: true)
        }
        timer.resume()
        fnHoldTimer = timer
    }

    private static func stopFnHoldRefreshLoop() {
        fnHoldTimer?.cancel()
        fnHoldTimer = nil
    }

    private static func activeSyntheticModifierFlags() -> CGEventFlags {
        var flags = CGEventFlags()
        for key in heldKeyCounts.keys {
            switch key {
            case .fn:
                flags.insert(.maskSecondaryFn)
            case let .modifier(code):
                if let flag = modifierFlag(forVirtualKey: code) {
                    flags.insert(flag)
                }
            case .regular:
                break
            }
        }
        return flags
    }

    /// Synthesizes modifier flags from hardware HID state (preserving physical
    /// modifiers and Caps Lock without picking up stale synthetic state) plus
    /// this process's currently active synthetic holds.
    static func synthesizedFlags(
        hardwareFlags: CGEventFlags,
        syntheticFlags: CGEventFlags,
        targetFlag: CGEventFlags,
        keyDown: Bool
    ) -> CGEventFlags {
        var combined = hardwareFlags.union(syntheticFlags)
        if keyDown {
            combined.insert(targetFlag)
        }
        return combined
    }

    private static func currentSynthesizedFlags(for targetFlag: CGEventFlags, keyDown: Bool) -> CGEventFlags {
        let hardwareFlags = CGEventSource.flagsState(.hidSystemState)
        return synthesizedFlags(
            hardwareFlags: hardwareFlags,
            syntheticFlags: activeSyntheticModifierFlags(),
            targetFlag: targetFlag,
            keyDown: keyDown
        )
    }

    private static func postFnFlagsChanged(keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0x3F, keyDown: keyDown) else { return }
        event.type = .flagsChanged
        event.flags = currentSynthesizedFlags(for: .maskSecondaryFn, keyDown: keyDown)
        event.post(tap: .cghidEventTap)
    }

    private static func modifierFlag(forVirtualKey code: CGKeyCode) -> CGEventFlags? {
        switch code {
        case 0x37: return .maskCommand
        case 0x38: return .maskShift
        case 0x3A: return .maskAlternate
        case 0x3B: return .maskControl
        default: return nil
        }
    }

    /// Post a single key-down or key-up event. Runs on `actionQueue` only.
    private static func postHoldKey(_ holdKey: HoldKey, keyDown: Bool) {
        switch holdKey {
        case .fn:
            postFnFlagsChanged(keyDown: keyDown)
        case let .modifier(virtualKey):
            let source = CGEventSource(stateID: .hidSystemState)
            guard let flag = modifierFlag(forVirtualKey: virtualKey),
                  let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else { return }
            event.type = .flagsChanged
            event.flags = currentSynthesizedFlags(for: flag, keyDown: keyDown)
            event.post(tap: .cghidEventTap)
        case let .regular(code):
            let source = CGEventSource(stateID: .hidSystemState)
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { return }
            let synthetic = activeSyntheticModifierFlags()
            if !synthetic.isEmpty {
                event.flags = CGEventSource.flagsState(.hidSystemState).union(synthetic)
            }
            event.post(tap: .cghidEventTap)
        }
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
            // Do not emit an interrupting fn-up if another control is actively holding fn.
            guard heldKeyCounts[.fn, default: 0] == 0 else { return }
            postFnKeyToggle()
            return
        }

        var flags = activeSyntheticModifierFlags()
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
        // If another control is currently holding this same virtual key, avoid
        // emitting key-up that would prematurely release the active hold.
        guard heldKeyCounts[.regular(code), default: 0] == 0 else { return }
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
        down.flags = currentSynthesizedFlags(for: .maskSecondaryFn, keyDown: true)
        up.flags = currentSynthesizedFlags(for: .maskSecondaryFn, keyDown: false)
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
    }

    private static func keyCode(for name: String) -> CGKeyCode? {
        VibeKeyKeyMap.virtualKey(for: name)
    }
}
