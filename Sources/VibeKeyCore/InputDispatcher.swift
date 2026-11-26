import Foundation

/// High-level action event emitted by `VibeKeyInputDispatcher`.
public enum VibeKeyInputTrigger: Equatable, Sendable {
    case shortPress(control: InputControl, action: ActionConfig)
    case longPressTap(control: InputControl, action: ActionConfig)
    case longPressHoldBegin(control: InputControl, action: ActionConfig)
    case longPressHoldEnd(control: InputControl, action: ActionConfig)
}

/// Main-actor timer seam for `VibeKeyInputDispatcher`, allowing production code
/// to schedule on `RunLoop.Mode.common` and unit tests to advance time
/// deterministically on the same actor.
@MainActor
public protocol VibeKeyInputScheduler: AnyObject {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject
    func cancel(_ token: AnyObject)
}

/// Default production scheduler using `RunLoop.main` in `.common` mode so
/// long-press timers keep firing even while menus or tracking loops are open.
@MainActor
public final class RunLoopCommonInputScheduler: VibeKeyInputScheduler {
    public init() {}

    public func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    public func cancel(_ token: AnyObject) {
        (token as? Timer)?.invalidate()
    }
}

/// Discriminates short presses, long-press taps, and long-press holds per
/// physical control while guaranteeing release on key-up, stray downs,
/// configuration changes, disconnect, wireless power-off, host sleep, or
/// termination. Confined to `@MainActor` so input handling, timers, and
/// cancellation share one execution context without races.
@MainActor
public final class VibeKeyInputDispatcher {
    public nonisolated static let defaultLongPressThreshold: TimeInterval = 0.2

    private struct PendingPress {
        let generation: UInt64
        let token: AnyObject
        let shortPressAction: ActionConfig
        let longPressAction: ActionConfig
    }

    private let longPressThreshold: TimeInterval
    private let scheduler: VibeKeyInputScheduler
    private let holdSupport: (ActionConfig) -> Bool
    private let onTrigger: (VibeKeyInputTrigger) -> Void

    private var nextGeneration: UInt64 = 0
    private var pendingPresses: [InputControl: PendingPress] = [:]
    private var heldLongPresses: [InputControl: ActionConfig] = [:]

    public init(
        longPressThreshold: TimeInterval = VibeKeyInputDispatcher.defaultLongPressThreshold,
        scheduler: VibeKeyInputScheduler? = nil,
        holdSupport: @escaping (ActionConfig) -> Bool = ActionPerformer.supportsHold,
        onTrigger: @escaping (VibeKeyInputTrigger) -> Void
    ) {
        self.longPressThreshold = longPressThreshold
        self.scheduler = scheduler ?? RunLoopCommonInputScheduler()
        self.holdSupport = holdSupport
        self.onTrigger = onTrigger
    }

    public var activeHeldControls: Set<InputControl> {
        Set(heldLongPresses.keys)
    }

    public var pendingControls: Set<InputControl> {
        Set(pendingPresses.keys)
    }

    /// Processes a physical button/knob event against the latest configuration.
    public func handle(
        control: InputControl,
        phase: ButtonPhase,
        configuration: VibeKeyConfiguration
    ) {
        switch phase {
        case .up:
            // Always release an active hold first, even if configuration changed
            // or disabled long-press while the user was holding the key.
            if let heldAction = heldLongPresses.removeValue(forKey: control) {
                onTrigger(.longPressHoldEnd(control: control, action: heldAction))
                return
            }
            if let pending = pendingPresses.removeValue(forKey: control) {
                scheduler.cancel(pending.token)
                onTrigger(.shortPress(control: control, action: pending.shortPressAction))
            }

        case .down:
            // Clean up any stray pending or held state for this control (e.g. missed key-up).
            if let pending = pendingPresses.removeValue(forKey: control) {
                scheduler.cancel(pending.token)
            }
            if let heldAction = heldLongPresses.removeValue(forKey: control) {
                onTrigger(.longPressHoldEnd(control: control, action: heldAction))
            }

            let shortAction = configuration.action(for: control)
            guard control.supportsLongPress,
                  let longPressAction = configuration.longPressAction(for: control) else {
                onTrigger(.shortPress(control: control, action: shortAction))
                return
            }

            nextGeneration &+= 1
            let generation = nextGeneration
            let token = scheduler.schedule(after: longPressThreshold) { [weak self] in
                self?.fireLongPress(control: control, generation: generation)
            }
            pendingPresses[control] = PendingPress(
                generation: generation,
                token: token,
                shortPressAction: shortAction,
                longPressAction: longPressAction
            )
        }
    }

    /// Cancels all pending long-press timers and releases every held action.
    /// Call on device disconnect, wireless power-off, host sleep, or app termination.
    public func cancelAll() {
        let pending = pendingPresses
        pendingPresses.removeAll()
        for entry in pending.values {
            scheduler.cancel(entry.token)
        }

        let held = heldLongPresses
        heldLongPresses.removeAll()
        for control in InputControl.allCases {
            if let action = held[control] {
                onTrigger(.longPressHoldEnd(control: control, action: action))
            }
        }
    }

    private func fireLongPress(control: InputControl, generation: UInt64) {
        guard let pending = pendingPresses[control],
              pending.generation == generation else { return }
        pendingPresses.removeValue(forKey: control)

        if holdSupport(pending.longPressAction) {
            heldLongPresses[control] = pending.longPressAction
            onTrigger(.longPressHoldBegin(control: control, action: pending.longPressAction))
        } else {
            onTrigger(.longPressTap(control: control, action: pending.longPressAction))
        }
    }
}
