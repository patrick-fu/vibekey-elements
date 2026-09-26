import XCTest
@testable import VibeKeyCore

final class VibeKeyCoreTests: XCTestCase {

    // MARK: - 1. TEA Codec Standard Vectors

    func testTEAEncryptionAndDecryptionStandardVectors() throws {
        // Vector 1: 01 06 50 01 00 00 00 00 -> 57 df 12 e6 02 d7 9d fd
        let plaintext1: [UInt8] = [0x01, 0x06, 0x50, 0x01, 0x00, 0x00, 0x00, 0x00]
        let expectedCipher1: [UInt8] = [0x57, 0xDF, 0x12, 0xE6, 0x02, 0xD7, 0x9D, 0xFD]

        let encrypted1 = try TEACodec.encrypt(plaintext1)
        XCTAssertEqual(encrypted1, expectedCipher1)

        let decrypted1 = try TEACodec.decrypt(encrypted1)
        XCTAssertEqual(decrypted1, plaintext1)

        // Vector 2: all zeros -> 38 90 c4 99 a3 60 aa ad
        let plaintextZeros = [UInt8](repeating: 0, count: 8)
        let expectedCipherZeros: [UInt8] = [0x38, 0x90, 0xC4, 0x99, 0xA3, 0x60, 0xAA, 0xAD]
        let encryptedZeros = try TEACodec.encrypt(plaintextZeros)
        XCTAssertEqual(encryptedZeros, expectedCipherZeros)

        let decryptedZeros = try TEACodec.decrypt(encryptedZeros)
        XCTAssertEqual(decryptedZeros, plaintextZeros)
    }

    func test64ByteReportFraming() throws {
        var plaintext = [UInt8](repeating: 0, count: 64)
        plaintext[0] = 0x06
        plaintext[1] = 0x01
        plaintext[2] = 0x23
        plaintext[4] = 0x01

        let report = try TEACodec.buildOutputReport(encrypting: plaintext)
        XCTAssertEqual(report.count, 64)
        XCTAssertEqual(report[0], VibeKeyDeviceInfo.reportID) // 0x55

        // Decrypt input report (stripping reportID 0x55)
        let decrypted = try TEACodec.decryptInputReport(report)
        XCTAssertEqual(decrypted.count, 56) // 7 complete 8-byte blocks
        XCTAssertEqual(decrypted[0], 0x06)
        XCTAssertEqual(decrypted[1], 0x01)
        XCTAssertEqual(decrypted[2], 0x23)
        XCTAssertEqual(decrypted[4], 0x01)
    }

    // MARK: - 2. Heartbeat & Software Online Packets

    func testHeartbeatAndOnlinePackets() throws {
        let heartbeatReport = try VibeKeyPacketBuilder.heartbeatReport()
        XCTAssertEqual(heartbeatReport.count, 64)
        XCTAssertEqual(heartbeatReport[0], 0x55)

        let onlineReport = try VibeKeyPacketBuilder.softwareOnlineReport(true)
        XCTAssertEqual(onlineReport.count, 64)

        let offlineReport = try VibeKeyPacketBuilder.softwareOnlineReport(false)
        XCTAssertEqual(offlineReport.count, 64)
    }

    // MARK: - 3. Battery and Power Response Parsing

    func testBatteryParsing() throws {
        // Mock plaintext response: 81 01 02 11 + [voltage: 3700mV (0x0E74)] + [percent: 75% (0x004B)] + 00 00 + [charging: 1] + [flags: 0x00]
        var plaintext = [UInt8](repeating: 0, count: 56)
        plaintext[0] = 0x81
        plaintext[1] = 0x01
        plaintext[2] = 0x02
        plaintext[3] = 0x11
        // Voltage 3700 mV = 0x0E74 (little-endian: 74 0E)
        plaintext[4] = 0x74
        plaintext[5] = 0x0E
        // Percent 75% = 0x004B (little-endian: 4B 00)
        plaintext[6] = 0x4B
        plaintext[7] = 0x00
        // Charging flag
        plaintext[10] = 0x01

        let response = VibeKeyParser.parsePowerResponse(plaintext: plaintext)
        guard case let .battery(status) = response else {
            XCTFail("Expected battery response")
            return
        }

        XCTAssertEqual(status.percent, 75)
        XCTAssertEqual(status.voltageMillivolts, 3700)
        XCTAssertTrue(status.isCharging)
    }

    func testStandbyAndSleepTimeParsing() throws {
        // Standby delay: 0x2C, value 600s = 0x00000258
        var plaintextStandby = [UInt8](repeating: 0, count: 56)
        plaintextStandby[0] = 0x81
        plaintextStandby[1] = 0x01
        plaintextStandby[2] = 0x2C
        plaintextStandby[3] = 0x11
        plaintextStandby[4] = 0x58
        plaintextStandby[5] = 0x02
        plaintextStandby[6] = 0x00
        plaintextStandby[7] = 0x00

        let standbyResp = VibeKeyParser.parsePowerResponse(plaintext: plaintextStandby)
        XCTAssertEqual(standbyResp, .standbyTime(seconds: 600))

        // Sleep delay: 0x42, value 3600s = 0x00000E10
        var plaintextSleep = [UInt8](repeating: 0, count: 56)
        plaintextSleep[0] = 0x81
        plaintextSleep[1] = 0x01
        plaintextSleep[2] = 0x42
        plaintextSleep[3] = 0x11
        plaintextSleep[4] = 0x10
        plaintextSleep[5] = 0x0E
        plaintextSleep[6] = 0x00
        plaintextSleep[7] = 0x00

        let sleepResp = VibeKeyParser.parsePowerResponse(plaintext: plaintextSleep)
        XCTAssertEqual(sleepResp, .sleepTime(seconds: 3600))
    }

    // MARK: - 4. Physical Event Notice Parsing

    func testPhysicalNoticeParsing() throws {
        // Event format: ?B 10 <logical> <status> <physicalIndex> ...
        // Top Button Down: 0B 10 6F 01 00
        let topDown: [UInt8] = [0x0B, 0x10, 0x6F, 0x01, 0x00, 0x00, 0x00, 0x00]
        let eventTopDown = VibeKeyParser.parseDeviceEvent(plaintext: topDown)
        XCTAssertEqual(eventTopDown, .key(control: .topButton, phase: .down))

        // Knob Press Down: 8B 10 6E 01 03
        let knobPressDown: [UInt8] = [0x8B, 0x10, 0x6E, 0x01, 0x03, 0x00, 0x00, 0x00]
        let eventKnobPressDown = VibeKeyParser.parseDeviceEvent(plaintext: knobPressDown)
        XCTAssertEqual(eventKnobPressDown, .key(control: .knobPress, phase: .down))

        // Knob Right (CW): 0B 10 00 00 04
        let knobRight: [UInt8] = [0x0B, 0x10, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00]
        let eventKnobRight = VibeKeyParser.parseDeviceEvent(plaintext: knobRight)
        XCTAssertEqual(eventKnobRight, .key(control: .knobRight, phase: .down))

        // Knob Left (CCW): 0B 10 00 00 05
        let knobLeft: [UInt8] = [0x0B, 0x10, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00]
        let eventKnobLeft = VibeKeyParser.parseDeviceEvent(plaintext: knobLeft)
        XCTAssertEqual(eventKnobLeft, .key(control: .knobLeft, phase: .down))
    }

    // MARK: - 5. LED Control & AI Agent Hooks

    func testLEDAndAgentHooksPackets() throws {
        // LED Set Packet
        let ledReport = try VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .breathing, brightness: 100)
        XCTAssertEqual(ledReport.count, 64)
        XCTAssertEqual(ledReport[0], 0x55)

        // Reset LED
        let resetReport = try VibeKeyPacketBuilder.resetLEDReport()
        XCTAssertEqual(resetReport.count, 64)

        // AI Agent Hooks Mode (0 = disabled, 1 = enabled)
        let hooksOn = try VibeKeyPacketBuilder.setAgentHooksModeReport(enabled: true)
        XCTAssertEqual(hooksOn.count, 64)
        let hooksOff = try VibeKeyPacketBuilder.setAgentHooksModeReport(enabled: false)
        XCTAssertEqual(hooksOff.count, 64)
    }

    // MARK: - 6. Action Execution Models

    func testActionConfigSerialization() throws {
        let config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["fn"]),
            middleButton: .keySequence(keys: ["return"]),
            bottomButton: .keySequence(keys: ["command", "delete"]),
            knobLeft: .mouseWheel(direction: .down),
            knobRight: .mouseWheel(direction: .up),
            knobPress: .keySequence(keys: ["option", "command", "a"])
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(VibeKeyConfiguration.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}
