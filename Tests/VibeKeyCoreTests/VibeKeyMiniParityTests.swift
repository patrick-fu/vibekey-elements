import XCTest
@testable import VibeKeyCore

final class VibeKeyMiniParityTests: XCTestCase {
    func testHumanReadableFnActionRoundTrip() throws {
        let action = ActionConfig.keySequence(keys: ["fn"])
        let text = ActionConfigTextCodec.encode(action)
        XCTAssertEqual(text, "Fn")
        XCTAssertEqual(try ActionConfigTextCodec.parse(text), action)
    }

    func testReadbackCollectorCollectsCoreDeviceStatus() throws {
        var collector = VibeKeyReadbackCollector()

        var firmware = [UInt8](repeating: 0, count: 56)
        firmware[0] = 0x81
        firmware[1] = 0x04
        firmware[2] = 0x04
        firmware[10] = 1
        firmware[11] = 0
        firmware[12] = 3

        var serial = [UInt8](repeating: 0, count: 56)
        serial[0] = 0x81
        serial[1] = 0x01
        serial[2] = 0x0B
        serial[4] = 6
        serial[5] = 0
        for (offset, byte) in "VK-05A".utf8.enumerated() { serial[6 + offset] = byte }

        var battery = [UInt8](repeating: 0, count: 56)
        battery[0] = 0x81
        battery[1] = 0x01
        battery[2] = 0x02
        battery[3] = 0x11
        battery[4] = 0x74
        battery[5] = 0x0E
        battery[6] = 75
        battery[10] = 1

        var standby = [UInt8](repeating: 0, count: 8)
        standby[0] = 0x81; standby[1] = 0x01; standby[2] = 0x2C; standby[3] = 0x11
        standby[4] = 44; standby[5] = 1

        var sleep = [UInt8](repeating: 0, count: 8)
        sleep[0] = 0x81; sleep[1] = 0x01; sleep[2] = 0x42; sleep[3] = 0x11
        sleep[4] = 16; sleep[5] = 14

        var noise = [UInt8](repeating: 0, count: 5)
        noise[0] = 0x81; noise[1] = 0x01; noise[2] = 0x90; noise[3] = 0x11; noise[4] = 2

        var mic = [UInt8](repeating: 0, count: 5)
        mic[0] = 0x81; mic[1] = 0x01; mic[2] = 0x2A; mic[3] = 0x11; mic[4] = 1

        XCTAssertNotNil(collector.ingest(plaintext: firmware))
        XCTAssertNotNil(collector.ingest(plaintext: serial))
        XCTAssertNotNil(collector.ingest(plaintext: battery))
        XCTAssertNotNil(collector.ingest(plaintext: standby))
        XCTAssertNotNil(collector.ingest(plaintext: sleep))
        XCTAssertNotNil(collector.ingest(plaintext: noise))
        XCTAssertNotNil(collector.ingest(plaintext: mic))

        let complete = collector.isQueryStatusComplete
        XCTAssertTrue(complete)
        let summary = collector.statusSummary()
        XCTAssertTrue(summary.contains("设备状态获取中"))
        XCTAssertTrue(summary.contains("电量: 75% (充电中, 3700mV)"))
        XCTAssertTrue(summary.contains("固件: 1.0.3"))
        XCTAssertTrue(summary.contains("序列号: VK-05A"))
        XCTAssertTrue(summary.contains("待机: 300s"))
        XCTAssertTrue(summary.contains("深度休眠: 3600s"))
        XCTAssertTrue(summary.contains("麦克风降噪: 2"))
        XCTAssertTrue(summary.contains("麦克风: 开启"))
    }

    func testReadbackCollectorDisplaysKnobRotationWithoutButtonPhase() throws {
        var collector = VibeKeyReadbackCollector()
        let knobRight = try XCTUnwrap(collector.ingest(plaintext: [0x0B, 0x10, 0x00, 0x00, 0x04]))
        XCTAssertEqual(VibeKeyReadbackCollector.display(knobRight), "旋钮右旋")

        let knobLeft = try XCTUnwrap(collector.ingest(plaintext: [0x0B, 0x10, 0x00, 0x00, 0x05]))
        XCTAssertEqual(VibeKeyReadbackCollector.display(knobLeft), "旋钮左旋")
    }

    func testReadbackCollectorRendersInputAndPowerOff() throws {
        var collector = VibeKeyReadbackCollector()
        let input = try XCTUnwrap(collector.ingest(plaintext: [0x0B, 0x10, 0x6F, 0x01, 0x00]))
        XCTAssertEqual(VibeKeyReadbackCollector.display(input), "K1 down")

        let poweredOff = try XCTUnwrap(collector.ingest(plaintext: [0x0B, 0x0B, 0x00]))
        XCTAssertEqual(VibeKeyReadbackCollector.display(poweredOff), "设备关机（接收器仍连接）")
        XCTAssertEqual(collector.snapshot.isDeviceOn, false)
    }

    func testFileLoggerTightensExistingBroadPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibekey-log-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o644])

        let logger = VibeKeyFileLogger(url: url)
        logger.log("power")
        logger.waitForPendingWrites()

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testFileLoggerWritesPrivateJSONLEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibekey-log-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("events.jsonl")
        let fixedDate = Date(timeIntervalSince1970: 1_789_000_000)
        let logger = VibeKeyFileLogger(url: url, now: { fixedDate })

        logger.log("power", fields: ["state": "off"])
        logger.log("device.attached")
        logger.waitForPendingWrites()

        let data = try Data(contentsOf: url)
        let lines = try XCTUnwrap(String(data: data, encoding: .utf8)?.split(separator: "\n"))
        XCTAssertEqual(lines.count, 2)
        let line = try XCTUnwrap(lines.first)
        XCTAssertTrue(line.contains("\"event\":\"power\""))
        XCTAssertTrue(line.contains("\"state\":\"off\""))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }
}
