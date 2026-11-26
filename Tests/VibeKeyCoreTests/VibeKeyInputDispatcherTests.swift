import CoreGraphics
import XCTest
@testable import VibeKeyCore

@MainActor
private final class ManualInputScheduler: VibeKeyInputScheduler {
    private final class Token {
        let fireAt: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false

        init(fireAt: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.action = action
        }
    }

    private(set) var now: TimeInterval = 0
    private var tokens: [Token] = []

    var activeTimerCount: Int {
        tokens.filter { !$0.cancelled }.count
    }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyObject {
        let token = Token(fireAt: now + delay, action: action)
        tokens.append(token)
        return token
    }

    func cancel(_ token: AnyObject) {
        (token as? Token)?.cancelled = true
    }

    func advance(by delta: TimeInterval) {
        now += delta
        while let index = tokens.firstIndex(where: { !$0.cancelled && $0.fireAt <= now }) {
            let token = tokens.remove(at: index)
            token.action()
        }
        tokens.removeAll(where: \.cancelled)
    }
}

@MainActor
final class VibeKeyInputDispatcherTests: XCTestCase {
    func testNoLongPressFiresShortPressImmediatelyOnKeyDown() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(scheduler: scheduler) { triggers.append($0) }
        let config = VibeKeyConfiguration(topButton: .keySequence(keys: ["fn"]))

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        XCTAssertEqual(triggers, [.shortPress(control: .topButton, action: .keySequence(keys: ["fn"]))])
        XCTAssertEqual(scheduler.activeTimerCount, 0)

        dispatcher.handle(control: .topButton, phase: .up, configuration: config)
        XCTAssertEqual(triggers.count, 1)
    }

    func testShortPressBeforeThresholdCancelsLongPressTimer() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["return"]),
            topButtonLongPress: .shellCommand(command: "echo long")
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        XCTAssertTrue(triggers.isEmpty)
        XCTAssertEqual(scheduler.activeTimerCount, 1)

        scheduler.advance(by: 0.15)
        dispatcher.handle(control: .topButton, phase: .up, configuration: config)
        XCTAssertEqual(triggers, [.shortPress(control: .topButton, action: .keySequence(keys: ["return"]))])
        XCTAssertEqual(scheduler.activeTimerCount, 0)

        scheduler.advance(by: 0.2)
        XCTAssertEqual(triggers.count, 1)
    }

    func testNonHoldableLongPressFiresTapAtThresholdAndIgnoresRelease() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let longAction = ActionConfig.keySequence(keys: ["command", "c"])
        let config = VibeKeyConfiguration(
            middleButton: .keySequence(keys: ["return"]),
            middleButtonLongPress: longAction
        )

        dispatcher.handle(control: .middleButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(triggers, [.longPressTap(control: .middleButton, action: longAction)])
        XCTAssertTrue(dispatcher.activeHeldControls.isEmpty)

        dispatcher.handle(control: .middleButton, phase: .up, configuration: config)
        XCTAssertEqual(triggers.count, 1)
    }

    func testHoldableLongPressBeginsAtThresholdAndEndsOnKeyUp() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let holdAction = ActionConfig.keySequence(keys: ["fn"])
        let config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["return"]),
            topButtonLongPress: holdAction
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(triggers, [.longPressHoldBegin(control: .topButton, action: holdAction)])
        XCTAssertEqual(dispatcher.activeHeldControls, [.topButton])

        dispatcher.handle(control: .topButton, phase: .up, configuration: config)
        XCTAssertEqual(triggers, [
            .longPressHoldBegin(control: .topButton, action: holdAction),
            .longPressHoldEnd(control: .topButton, action: holdAction)
        ])
        XCTAssertTrue(dispatcher.activeHeldControls.isEmpty)
    }

    func testDisablingLongPressMidHoldStillReleasesHeldKeyOnKeyUp() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let holdAction = ActionConfig.keySequence(keys: ["control"])
        var config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["return"]),
            topButtonLongPress: holdAction
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(dispatcher.activeHeldControls, [.topButton])

        config.topButtonLongPress = nil
        dispatcher.handle(control: .topButton, phase: .up, configuration: config)

        XCTAssertEqual(triggers, [
            .longPressHoldBegin(control: .topButton, action: holdAction),
            .longPressHoldEnd(control: .topButton, action: holdAction)
        ])
        XCTAssertTrue(dispatcher.activeHeldControls.isEmpty)
    }

    func testStraySecondKeyDownReleasesPriorHeldKey() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let holdAction = ActionConfig.keySequence(keys: ["fn"])
        let config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["return"]),
            topButtonLongPress: holdAction
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.2)
        XCTAssertEqual(dispatcher.activeHeldControls, [.topButton])

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        XCTAssertEqual(triggers, [
            .longPressHoldBegin(control: .topButton, action: holdAction),
            .longPressHoldEnd(control: .topButton, action: holdAction)
        ])
        XCTAssertTrue(dispatcher.activeHeldControls.isEmpty)
        XCTAssertEqual(dispatcher.pendingControls, [.topButton])
    }

    func testSimultaneousMultiKeyPressesDoNotSwallowOrOverwriteEachOther() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let k1Short = ActionConfig.keySequence(keys: ["a"])
        let k1Long = ActionConfig.keySequence(keys: ["fn"])
        let k2Short = ActionConfig.keySequence(keys: ["b"])
        let k2Long = ActionConfig.keySequence(keys: ["control"])
        let config = VibeKeyConfiguration(
            topButton: k1Short,
            middleButton: k2Short,
            topButtonLongPress: k1Long,
            middleButtonLongPress: k2Long
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.05)
        dispatcher.handle(control: .middleButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.05)
        dispatcher.handle(control: .topButton, phase: .up, configuration: config)
        scheduler.advance(by: 0.16)
        dispatcher.handle(control: .middleButton, phase: .up, configuration: config)

        XCTAssertEqual(triggers, [
            .shortPress(control: .topButton, action: k1Short),
            .longPressHoldBegin(control: .middleButton, action: k2Long),
            .longPressHoldEnd(control: .middleButton, action: k2Long)
        ])
    }

    func testCancelAllCancelsPendingTimersAndReleasesEveryHeldControl() {
        let scheduler = ManualInputScheduler()
        var triggers: [VibeKeyInputTrigger] = []
        let dispatcher = VibeKeyInputDispatcher(longPressThreshold: 0.2, scheduler: scheduler) { triggers.append($0) }
        let k1Hold = ActionConfig.keySequence(keys: ["fn"])
        let k2Hold = ActionConfig.keySequence(keys: ["control"])
        let config = VibeKeyConfiguration(
            topButtonLongPress: k1Hold,
            middleButtonLongPress: k2Hold
        )

        dispatcher.handle(control: .topButton, phase: .down, configuration: config)
        scheduler.advance(by: 0.2)
        dispatcher.handle(control: .middleButton, phase: .down, configuration: config)

        XCTAssertEqual(dispatcher.activeHeldControls, [.topButton])
        XCTAssertEqual(dispatcher.pendingControls, [.middleButton])

        dispatcher.cancelAll()

        XCTAssertTrue(dispatcher.activeHeldControls.isEmpty)
        XCTAssertTrue(dispatcher.pendingControls.isEmpty)
        XCTAssertEqual(scheduler.activeTimerCount, 0)
        XCTAssertEqual(triggers, [
            .longPressHoldBegin(control: .topButton, action: k1Hold),
            .longPressHoldEnd(control: .topButton, action: k1Hold)
        ])

        scheduler.advance(by: 0.5)
        XCTAssertEqual(triggers.count, 2)
    }

    func testSupportsHoldAndCanonicalKeyAliases() {
        XCTAssertTrue(ActionPerformer.supportsHold(.keySequence(keys: ["fn"])))
        XCTAssertTrue(ActionPerformer.supportsHold(.keySequence(keys: ["control"])))
        XCTAssertTrue(ActionPerformer.supportsHold(.keySequence(keys: ["⌘"])))
        XCTAssertTrue(ActionPerformer.supportsHold(.keySequence(keys: ["f12"])))
        XCTAssertTrue(ActionPerformer.supportsHold(.keySequence(keys: ["space"])))

        XCTAssertEqual(
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["return"])),
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["enter"]))
        )
        XCTAssertEqual(
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["delete"])),
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["backspace"]))
        )
        XCTAssertEqual(
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["command"])),
            ActionPerformer.canonicalHoldKey(for: .keySequence(keys: ["⌘"]))
        )

        XCTAssertFalse(ActionPerformer.supportsHold(.keySequence(keys: [])))
        XCTAssertFalse(ActionPerformer.supportsHold(.keySequence(keys: ["command", "c"])))
        XCTAssertFalse(ActionPerformer.supportsHold(.keySequence(keys: ["unknown_key_xyz"])))
        XCTAssertFalse(ActionPerformer.supportsHold(.mouseWheel(direction: .up)))
        XCTAssertFalse(ActionPerformer.supportsHold(.shellCommand(command: "echo hi")))
    }

    func testSynthesizedFlagsPreservePhysicalModifiersAndCapsLock() {
        let releasedWithPhysicalShift = ActionPerformer.synthesizedFlags(
            hardwareFlags: [.maskShift, .maskAlphaShift],
            syntheticFlags: [.maskControl],
            targetFlag: .maskShift,
            keyDown: false
        )
        XCTAssertTrue(releasedWithPhysicalShift.contains(.maskShift))
        XCTAssertTrue(releasedWithPhysicalShift.contains(.maskAlphaShift))
        XCTAssertTrue(releasedWithPhysicalShift.contains(.maskControl))

        let releasedWithoutPhysicalShift = ActionPerformer.synthesizedFlags(
            hardwareFlags: [.maskAlphaShift],
            syntheticFlags: [],
            targetFlag: .maskShift,
            keyDown: false
        )
        XCTAssertFalse(releasedWithoutPhysicalShift.contains(.maskShift))
        XCTAssertTrue(releasedWithoutPhysicalShift.contains(.maskAlphaShift))
    }

    func testStandaloneModifierRecordingAndParsingForLongPress() throws {
        var shortBuffer = ShortcutRecordingBuffer()
        XCTAssertNil(shortBuffer.recordModifierChange(flags: [.maskControl]))
        XCTAssertNil(shortBuffer.recordModifierChange(flags: []))
        XCTAssertThrowsError(try ActionConfigTextCodec.parse("Control"))

        var longBuffer = ShortcutRecordingBuffer(allowStandaloneModifier: true)
        XCTAssertNil(longBuffer.recordModifierChange(flags: [.maskControl]))
        let recorded = longBuffer.recordModifierChange(flags: [])
        XCTAssertEqual(recorded, RecordedShortcut(keys: ["control"]))
        XCTAssertEqual(recorded?.display, "⌃")

        let encoded = ActionConfigTextCodec.encode(.keySequence(keys: ["control"]))
        XCTAssertEqual(encoded, "⌃")
        XCTAssertEqual(
            try ActionConfigTextCodec.parse(encoded, allowStandaloneModifier: true),
            .keySequence(keys: ["control"])
        )
        XCTAssertEqual(
            try ActionConfigTextCodec.parse("Command", allowStandaloneModifier: true),
            .keySequence(keys: ["command"])
        )
    }
}
