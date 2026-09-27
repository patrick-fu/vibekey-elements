import XCTest
@testable import VibeKeyCore

final class VibeKeyAblationTests: XCTestCase {

    // MARK: - Ablation 1: Non-8-byte aligned payload handling

    /// Verify that passing unaligned buffers throws a controlled error
    /// instead of causing out-of-bounds memory access or undefined behavior.
    func testAblationUnalignedPayloadSafety() {
        let unalignedPlaintext: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05] // 5 bytes
        XCTAssertThrowsError(try TEACodec.encrypt(unalignedPlaintext)) { error in
            XCTAssertEqual(error as? TEACodecError, .invalidPlaintextLength(actual: 5))
        }

        let unalignedCiphertext: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07] // 7 bytes
        XCTAssertThrowsError(try TEACodec.decrypt(unalignedCiphertext)) { error in
            XCTAssertEqual(error as? TEACodecError, .invalidCiphertextLength(actual: 7))
        }
    }

    // MARK: - Ablation 2: Report ID 0x55 framing tolerance

    /// Input reports can arrive either with 0x55 prepended (64 bytes total)
    /// or with 0x55 already stripped by the driver (63 bytes total).
    /// Verify that both variants correctly decrypt without off-by-one byte drift.
    func testAblationReportIDFramingTolerance() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext[0] = 0x06
        plaintext[1] = 0x01
        plaintext[2] = 0x23
        plaintext[4] = 0x01

        let outputReportWith55 = try TEACodec.buildOutputReport(encrypting: plaintext) // 64 bytes, starting with 0x55
        let decryptedFromFullReport = try TEACodec.decryptInputReport(outputReportWith55)
        XCTAssertEqual(decryptedFromFullReport[0], 0x06)
        XCTAssertEqual(decryptedFromFullReport[2], 0x23)

        // Variant without 0x55 (first byte dropped by driver)
        let strippedReport = Array(outputReportWith55.dropFirst()) // 63 bytes
        let decryptedFromStrippedReport = try TEACodec.decryptInputReport(strippedReport, hasReportID: false)
        XCTAssertEqual(decryptedFromStrippedReport[0], 0x06)
        XCTAssertEqual(decryptedFromStrippedReport[2], 0x23)
    }

    // MARK: - Ablation 3: LED Channel & Noise Reduction Boundary Interception

    /// Channel must not exceed 3, preventing index out of bounds fatal traps.
    func testAblationChannelBoundaryGuard() {
        XCTAssertNoThrow(try VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .solid, brightness: 100))
        XCTAssertNoThrow(try VibeKeyPacketBuilder.setLEDReport(channel: 3, mode: .breathing, brightness: 50))
        
        // Channel >= 4 must throw invalidChannel error
        XCTAssertThrowsError(try VibeKeyPacketBuilder.setLEDReport(channel: 4, mode: .solid, brightness: 100)) { error in
            XCTAssertEqual(error as? VibeKeyProtocolError, .invalidChannel(4))
        }
        XCTAssertThrowsError(try VibeKeyPacketBuilder.setLEDReport(channel: 255, mode: .off, brightness: 0)) { error in
            XCTAssertEqual(error as? VibeKeyProtocolError, .invalidChannel(255))
        }
    }

    /// Destructive validation for Noise Reduction level boundaries:
    /// Valid range is [0, 3]. Any level >= 4 (including extreme values like 4, 100, 255)
    /// must be strictly rejected at packet generation time with invalidNoiseReductionLevel.
    func testAblationNoiseReductionBoundaryInterception() {
        // Valid levels 0..3 must succeed
        for validLevel: UInt8 in 0...3 {
            XCTAssertNoThrow(try VibeKeyPacketBuilder.setNoiseReductionReport(level: validLevel))
        }

        // Boundary violation: exact boundary + 1 (level 4)
        XCTAssertThrowsError(try VibeKeyPacketBuilder.setNoiseReductionReport(level: 4)) { error in
            XCTAssertEqual(error as? VibeKeyProtocolError, .invalidNoiseReductionLevel(4))
        }

        // Extreme values and arbitrary out-of-range inputs
        let invalidLevels: [UInt8] = [5, 10, 50, 100, 127, 128, 200, 254, 255]
        for invalidLevel in invalidLevels {
            XCTAssertThrowsError(try VibeKeyPacketBuilder.setNoiseReductionReport(level: invalidLevel)) { error in
                XCTAssertEqual(error as? VibeKeyProtocolError, .invalidNoiseReductionLevel(invalidLevel))
            }
        }
    }

    // MARK: - Ablation 4: Configuration Deserialization Backward & Forward Compatibility

    /// Verify configuration deserialization resilience when backward-compatible legacy
    /// or partially populated JSON data is encountered.
    func testAblationConfigurationBackwardCompatibility() throws {
        // 1. Completely empty JSON: must fall back to all defaults safely
        let emptyJson = "{}".data(using: .utf8)!
        let emptyConfig = try JSONDecoder().decode(VibeKeyConfiguration.self, from: emptyJson)
        XCTAssertEqual(emptyConfig.topButton, .keySequence(keys: ["fn"]))
        XCTAssertEqual(emptyConfig.middleButton, .keySequence(keys: ["return"]))
        XCTAssertEqual(emptyConfig.bottomButton, .keySequence(keys: ["command", "delete"]))
        XCTAssertEqual(emptyConfig.knobLeft, .mouseWheel(direction: .down))
        XCTAssertEqual(emptyConfig.knobRight, .mouseWheel(direction: .up))
        XCTAssertEqual(emptyConfig.knobPress, .keySequence(keys: ["option", "command", "a"]))
        XCTAssertEqual(emptyConfig.micNoiseReduction, 0)
        XCTAssertEqual(emptyConfig.micEnabled, true)
        XCTAssertEqual(emptyConfig.ledMode, .auto)
        XCTAssertEqual(emptyConfig.standbySeconds, 300)
        XCTAssertEqual(emptyConfig.sleepSeconds, 3600)

        // 2. Legacy v1 JSON (pre-microphone & pre-sleep parameters)
        let legacyJson = """
        {
            "topButton": {"type": "keySequence", "keys": ["f18"]},
            "middleButton": {"type": "keySequence", "keys": ["f19"]},
            "bottomButton": {"type": "shellCommand", "command": "echo hello"},
            "knobLeft": {"type": "mouseWheel", "direction": "down"},
            "knobRight": {"type": "mouseWheel", "direction": "up"},
            "knobPress": {"type": "keySequence", "keys": ["command", "space"]}
        }
        """.data(using: .utf8)!

        let legacyConfig = try JSONDecoder().decode(VibeKeyConfiguration.self, from: legacyJson)
        XCTAssertEqual(legacyConfig.topButton, .keySequence(keys: ["f18"]))
        XCTAssertEqual(legacyConfig.middleButton, .keySequence(keys: ["f19"]))
        XCTAssertEqual(legacyConfig.bottomButton, .shellCommand(command: "echo hello"))
        XCTAssertEqual(legacyConfig.knobPress, .keySequence(keys: ["command", "space"]))
        // Missing fields must default gracefully to factory values
        XCTAssertEqual(legacyConfig.micNoiseReduction, 0)
        XCTAssertEqual(legacyConfig.micEnabled, true)
        XCTAssertEqual(legacyConfig.ledMode, .auto)
        XCTAssertEqual(legacyConfig.standbySeconds, 300)
        XCTAssertEqual(legacyConfig.sleepSeconds, 3600)

        // 3. Partial JSON: Mic configured but sleep/standby missing
        let micOnlyJson = """
        {
            "micNoiseReduction": 2,
            "micEnabled": false
        }
        """.data(using: .utf8)!

        let micConfig = try JSONDecoder().decode(VibeKeyConfiguration.self, from: micOnlyJson)
        XCTAssertEqual(micConfig.micNoiseReduction, 2)
        XCTAssertEqual(micConfig.micEnabled, false)
        XCTAssertEqual(micConfig.standbySeconds, 300)
        XCTAssertEqual(micConfig.sleepSeconds, 3600)
        XCTAssertEqual(micConfig.ledMode, .auto)

        // 4. Partial JSON: Sleep/standby configured but mic missing
        let sleepOnlyJson = """
        {
            "standbySeconds": 900,
            "sleepSeconds": 7200,
            "ledMode": "breathing"
        }
        """.data(using: .utf8)!

        let sleepConfig = try JSONDecoder().decode(VibeKeyConfiguration.self, from: sleepOnlyJson)
        XCTAssertEqual(sleepConfig.standbySeconds, 900)
        XCTAssertEqual(sleepConfig.sleepSeconds, 7200)
        XCTAssertEqual(sleepConfig.ledMode, .breathing)
        XCTAssertEqual(sleepConfig.micNoiseReduction, 0)
        XCTAssertEqual(sleepConfig.micEnabled, true)
    }

    // MARK: - Ablation 5: Short & Truncated Packet Boundary Guards

    /// Destructive validation for response parser boundary checks:
    /// In an untrusted HID transport environment, truncated or corrupt packets
    /// (e.g., buffer underflow with count < 5 for 0x90 and 0x2A) must return nil
    /// and NEVER trigger an index out of range crash or heap corruption.
    func testAblationShortPacketBoundaryGuards() {
        // Test short packet slice lengths [0, 1, 2, 3, 4] for 0x90 (Noise Reduction)
        let fullNRPlaintext: [UInt8] = [0x81, 0x01, 0x90, 0x11, 0x02] // count = 5
        for length in 0..<5 {
            let truncated = Array(fullNRPlaintext.prefix(length))
            let result = VibeKeyParser.parsePowerResponse(plaintext: truncated)
            XCTAssertNil(result, "Expected nil when parsing truncated 0x90 packet of length \(length)")
        }

        // Test short packet slice lengths [0, 1, 2, 3, 4] for 0x2A (Mic Enable)
        let fullMicPlaintext: [UInt8] = [0x81, 0x01, 0x2A, 0x11, 0x01] // count = 5
        for length in 0..<5 {
            let truncated = Array(fullMicPlaintext.prefix(length))
            let result = VibeKeyParser.parsePowerResponse(plaintext: truncated)
            XCTAssertNil(result, "Expected nil when parsing truncated 0x2A packet of length \(length)")
        }

        // Exact boundary condition (length == 5): must parse successfully
        let validNR = VibeKeyParser.parsePowerResponse(plaintext: fullNRPlaintext)
        XCTAssertEqual(validNR, .micNR(level: 2))

        let validMic = VibeKeyParser.parsePowerResponse(plaintext: fullMicPlaintext)
        XCTAssertEqual(validMic, .micEnabled(true))

        // Boundary checks for Standby (0x2C) and Sleep (0x42): require count >= 8
        let fullStandby: [UInt8] = [0x81, 0x01, 0x2C, 0x11, 0x58, 0x02, 0x00, 0x00]
        for length in 0..<8 {
            let truncated = Array(fullStandby.prefix(length))
            XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: truncated))
        }
        XCTAssertEqual(VibeKeyParser.parsePowerResponse(plaintext: fullStandby), .standbyTime(seconds: 600))

        let fullSleep: [UInt8] = [0x81, 0x01, 0x42, 0x11, 0x10, 0x0E, 0x00, 0x00]
        for length in 0..<8 {
            let truncated = Array(fullSleep.prefix(length))
            XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: truncated))
        }
        XCTAssertEqual(VibeKeyParser.parsePowerResponse(plaintext: fullSleep), .sleepTime(seconds: 3600))

        // Battery (0x02): requires count >= 11
        var fullBattery = [UInt8](repeating: 0, count: 11)
        fullBattery[0] = 0x81
        fullBattery[1] = 0x01
        fullBattery[2] = 0x02
        fullBattery[3] = 0x11
        fullBattery[4] = 0x74
        fullBattery[5] = 0x0E
        fullBattery[6] = 0x64 // 100%
        fullBattery[7] = 0x00
        fullBattery[10] = 0x01
        for length in 0..<11 {
            let truncated = Array(fullBattery.prefix(length))
            XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: truncated))
        }
        XCTAssertNotNil(VibeKeyParser.parsePowerResponse(plaintext: fullBattery))
    }

    /// Corrupted header flags ablation:
    /// Even with count >= 5, if byte 0, 1 or 3 do not match protocol expectations,
    /// the parser must safely return nil.
    func testAblationCorruptedHeaderFlags() {
        // Invalid byte 0 (not 0x01 in lowest 5 bits)
        let badByte0: [UInt8] = [0x00, 0x01, 0x90, 0x11, 0x02]
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: badByte0))

        // Invalid byte 1 (not 0x01)
        let badByte1: [UInt8] = [0x81, 0x02, 0x90, 0x11, 0x02]
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: badByte1))

        // Invalid byte 3 flag bits ((byte[3] & 0x11) != 0x11)
        let badFlags1: [UInt8] = [0x81, 0x01, 0x90, 0x10, 0x02] // missing 0x01 bit
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: badFlags1))

        let badFlags2: [UInt8] = [0x81, 0x01, 0x90, 0x01, 0x02] // missing 0x10 bit
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: badFlags2))

        let badFlags3: [UInt8] = [0x81, 0x01, 0x2A, 0x00, 0x01] // zero flags
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: badFlags3))

        // Unknown command byte 2
        let unknownCmd: [UInt8] = [0x81, 0x01, 0xFE, 0x11, 0x00]
        XCTAssertNil(VibeKeyParser.parsePowerResponse(plaintext: unknownCmd))
    }

    // MARK: - Ablation 6: Power Saving & Standby Idempotence

    func testAblationPowerSavingDuplicateInvocations() {
        let manager = VibeKeyHIDManager()
        var transitions: [Bool] = []
        manager.onPowerSavingChanged = { transitions.append($0) }

        // Calling enterPowerSaving multiple times must be idempotent
        manager.enterPowerSaving(isStandby: true)
        XCTAssertTrue(manager.isPowerSaving)
        XCTAssertTrue(manager.currentSnapshot.isStandby)
        manager.enterPowerSaving(isStandby: true)
        XCTAssertTrue(manager.isPowerSaving)
        XCTAssertEqual(transitions, [true])

        // Calling resumeFromPowerSaving multiple times must be idempotent
        manager.resumeFromPowerSaving()
        XCTAssertFalse(manager.isPowerSaving)
        XCTAssertFalse(manager.currentSnapshot.isStandby)
        manager.resumeFromPowerSaving()
        XCTAssertFalse(manager.isPowerSaving)
        XCTAssertEqual(transitions, [true, false])
    }

    func testAblationStandbyTimeoutBoundaryGuards() {
        let manager = VibeKeyHIDManager()
        // 0 seconds represents "Never Standby" and sets timeout to 0 (disabling idle standby)
        manager.setStandbyTimeout(seconds: 0)
        XCTAssertEqual(manager.standbyTimeoutSeconds, 0)

        // Normal value should update
        manager.setStandbyTimeout(seconds: 1800)
        XCTAssertEqual(manager.standbyTimeoutSeconds, 1800)
    }

    func testAblationTransientActivityNoticeDoesNotToggleStandby() {
        let manager = VibeKeyHIDManager()
        manager.applyDeviceNotice(.active(isActive: false))
        XCTAssertFalse(manager.isPowerSaving)
        XCTAssertFalse(manager.currentSnapshot.isStandby)

        manager.applyDeviceNotice(.active(isActive: true))
        XCTAssertFalse(manager.isPowerSaving)
        XCTAssertFalse(manager.currentSnapshot.isStandby)
    }

    func testAblationStandbyWakeActivityNoticeConfirmsResume() {
        let manager = VibeKeyHIDManager()
        manager.applyDeviceNotice(.standby(isStandby: true))
        XCTAssertTrue(manager.isPowerSaving)
        XCTAssertTrue(manager.currentSnapshot.isStandby)

        manager.applyDeviceNotice(.active(isActive: false))
        XCTAssertTrue(manager.isPowerSaving)
        XCTAssertTrue(manager.currentSnapshot.isStandby)

        manager.applyDeviceNotice(.active(isActive: true))
        XCTAssertFalse(manager.isPowerSaving)
        XCTAssertFalse(manager.currentSnapshot.isStandby)
    }

}
