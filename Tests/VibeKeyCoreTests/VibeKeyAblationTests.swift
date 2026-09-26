import XCTest
@testable import VibeKeyCore

final class VibeKeyAblationTests: XCTestCase {

    /// Ablation 1: Non-8-byte aligned payload handling.
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

    /// Ablation 2: Report ID 0x55 framing tolerance & false-positive collision.
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

    /// Ablation 3: Reviewer P0 Check - LED channel boundary guard.
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

        // Noise reduction boundary check
        XCTAssertNoThrow(try VibeKeyPacketBuilder.setNoiseReductionReport(level: 3))
        XCTAssertThrowsError(try VibeKeyPacketBuilder.setNoiseReductionReport(level: 4)) { error in
            XCTAssertEqual(error as? VibeKeyProtocolError, .invalidNoiseReductionLevel(4))
        }
    }

    /// Ablation 4: Configuration missing fields forward compatibility.
    func testAblationForwardCompatibleConfigurationDecoding() throws {
        // Partial JSON missing middleButton and knobPress
        let partialJson = """
        {
            "topButton": {"type": "keySequence", "keys": ["f18"]}
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(VibeKeyConfiguration.self, from: partialJson)
        XCTAssertEqual(config.topButton, .keySequence(keys: ["f18"]))
        // Falls back to safe default
        XCTAssertEqual(config.middleButton, .keySequence(keys: ["return"]))
        XCTAssertEqual(config.knobPress, .keySequence(keys: ["option", "command", "a"]))
    }
}
