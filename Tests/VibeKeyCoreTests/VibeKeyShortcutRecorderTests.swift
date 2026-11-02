import CoreGraphics
import XCTest
@testable import VibeKeyCore

final class VibeKeyShortcutRecorderTests: XCTestCase {
    func testKeyCodeNameRoundTrip() {
        let cases: [(CGKeyCode, String)] = [
            (0x24, "return"),
            (0x33, "delete"),
            (0x35, "escape"),
            (0x7B, "left"),
            (111, "f12"),
            (18, "1")
        ]

        for (code, name) in cases {
            XCTAssertEqual(VibeKeyKeyMap.name(for: code), name)
            XCTAssertEqual(VibeKeyKeyMap.virtualKey(for: name), code)
        }
    }

    func testRecordModifierCombination() throws {
        var recorder = ShortcutRecordingBuffer()
        recorder.update(flags: [.maskCommand])
        XCTAssertEqual(recorder.partialDisplay, "⌘")

        let shortcut = try XCTUnwrap(recorder.record(keyCode: 0x33, flags: [.maskCommand]))
        XCTAssertEqual(shortcut.keys, ["command", "delete"])
        XCTAssertEqual(shortcut.display, "⌘⌫")
        XCTAssertEqual(shortcut.actionConfig, .keySequence(keys: ["command", "delete"]))
    }

    func testModifierOrderIsCanonical() throws {
        var recorder = ShortcutRecordingBuffer()
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let shortcut = try XCTUnwrap(recorder.record(keyCode: 0x00, flags: flags))

        XCTAssertEqual(shortcut.keys, ["control", "option", "shift", "command", "a"])
        XCTAssertEqual(shortcut.display, "⌃⌥⇧⌘A")
    }

    func testRecordFnOnlyWhenReleasedWithoutTarget() throws {
        var recorder = ShortcutRecordingBuffer()
        recorder.update(flags: [.maskSecondaryFn])
        XCTAssertEqual(recorder.partialDisplay, "Fn")

        let shortcut = try XCTUnwrap(recorder.recordModifierChange(flags: []))
        XCTAssertEqual(shortcut, .init(keys: ["fn"]))
        XCTAssertEqual(shortcut.display, "Fn")
    }

    func testFnWithFunctionKeyDoesNotBecomeFnOnly() throws {
        var recorder = ShortcutRecordingBuffer()
        recorder.update(flags: [.maskSecondaryFn])

        let shortcut = try XCTUnwrap(recorder.record(keyCode: 111, flags: [.maskSecondaryFn]))
        XCTAssertEqual(shortcut.keys, ["fn", "f12"])
    }

    func testUnknownTargetDoesNotProduceShortcut() {
        var recorder = ShortcutRecordingBuffer()
        recorder.update(flags: [.maskCommand])

        XCTAssertNil(recorder.record(keyCode: 999, flags: [.maskCommand]))
        XCTAssertEqual(recorder.partialDisplay, "⌘")
    }

    func testNonShortcutFlagsAreIgnored() throws {
        var recorder = ShortcutRecordingBuffer()
        let capsLock = CGEventFlags(rawValue: 1 << 16)
        recorder.update(flags: [.maskCommand, capsLock])

        XCTAssertEqual(recorder.partialDisplay, "⌘")
        let shortcut = try XCTUnwrap(recorder.record(keyCode: 0x00, flags: [.maskCommand, capsLock]))
        XCTAssertEqual(shortcut.keys, ["command", "a"])
    }
}
