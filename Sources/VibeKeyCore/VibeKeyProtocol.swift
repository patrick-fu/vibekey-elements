import Foundation

public enum VibeKeyProtocolError: Error, Equatable, LocalizedError {
    case invalidChannel(UInt8)
    case invalidNoiseReductionLevel(UInt8)

    public var errorDescription: String? {
        switch self {
        case let .invalidChannel(channel):
            return "Invalid LED channel: \(channel). Must be 0...3."
        case let .invalidNoiseReductionLevel(level):
            return "Invalid NR level: \(level). Must be 0...3."
        }
    }
}

public enum VibeKeyPacketBuilder {
    public static func heartbeatReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x06
        plaintext[1] = 0x01
        plaintext[2] = 0x23
        plaintext[4] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func softwareOnlineReport(_ enabled: Bool) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x10
        plaintext[4] = enabled ? 0x03 : 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func powerQueryReport(commandID: UInt8) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = commandID
        plaintext[3] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func firmwareVersionQueryReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x04
        plaintext[2] = 0x04
        plaintext[3] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func serialNumberQueryReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x0B
        plaintext[3] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setStandbyTimeoutReport(seconds: UInt32) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x2C
        plaintext[3] = 0x02
        plaintext[4] = UInt8(truncatingIfNeeded: seconds)
        plaintext[5] = UInt8(truncatingIfNeeded: seconds >> 8)
        plaintext[6] = UInt8(truncatingIfNeeded: seconds >> 16)
        plaintext[7] = UInt8(truncatingIfNeeded: seconds >> 24)
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setSleepTimeoutReport(seconds: UInt32) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x42
        plaintext[3] = 0x02
        plaintext[4] = UInt8(truncatingIfNeeded: seconds)
        plaintext[5] = UInt8(truncatingIfNeeded: seconds >> 8)
        plaintext[6] = UInt8(truncatingIfNeeded: seconds >> 16)
        plaintext[7] = UInt8(truncatingIfNeeded: seconds >> 24)
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setLEDReport(channel: UInt8, mode: LEDMode, brightness: UInt8 = 100) throws -> [UInt8] {
        guard channel <= 3 else {
            throw VibeKeyProtocolError.invalidChannel(channel)
        }
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x88
        plaintext[3] = 0x04

        switch mode {
        case .auto:
            return try resetLEDReport()
        case .solid:
            plaintext[4] = 0x01
            plaintext[5] = 0x00
            plaintext[6] = 0x01 // Mode 1: solid on
        case .breathing:
            plaintext[4] = 0x7C
            plaintext[5] = channel
            for i in 0..<4 {
                let base = 8 + 5 * i
                plaintext[base] = 0x02
                plaintext[base + 1] = 0x0A
                plaintext[base + 2] = 0x02
                plaintext[base + 3] = 0x02
                plaintext[base + 4] = 0x02
            }
        case .off:
            plaintext[4] = 0x01
            plaintext[5] = 0x00
            plaintext[6] = 0x00 // Mode 0: off
        }

        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func resetLEDReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x88
        plaintext[3] = 0x04
        plaintext[4] = 0x01 // Reset to mode
        plaintext[5] = 0x00
        plaintext[6] = 0x02 // Mode 2 is hardware auto (factory default)
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setAgentHooksModeReport(enabled: Bool) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x89
        plaintext[3] = 0x04
        plaintext[4] = enabled ? 0x01 : 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setNoiseReductionReport(level: UInt8) throws -> [UInt8] {
        guard level <= 3 else {
            throw VibeKeyProtocolError.invalidNoiseReductionLevel(level)
        }
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x90
        plaintext[3] = 0x04
        plaintext[4] = level
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func noiseReductionQueryReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x90
        plaintext[3] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setMicrophoneEnableReport(enabled: Bool) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x2A
        plaintext[3] = 0x00
        plaintext[4] = enabled ? 0x01 : 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func microphoneEnableQueryReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x2A
        plaintext[3] = 0x01
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func rebootReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x0C
        plaintext[3] = 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setHooksModeReport(enabled: Bool) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x89
        plaintext[3] = 0x04
        plaintext[4] = enabled ? 0x01 : 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setAudioButtonSystemModeReport(enabled: Bool) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x06
        plaintext[2] = 0x51
        plaintext[3] = 0x04
        plaintext[4] = enabled ? 0x01 : 0x00
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }
}

public enum VibeKeyParser {
    public static func parseDeviceEvent(plaintext: [UInt8]) -> DeviceEvent? {
        guard plaintext.count >= 5,
              (plaintext[0] & 0x1F) == 0x0B,
              plaintext[1] == 0x10 else {
            return nil
        }

        let control: InputControl
        switch plaintext[4] {
        case 0: control = .topButton
        case 1: control = .middleButton
        case 2: control = .bottomButton
        case 3: control = .knobPress
        case 4: return .key(control: .knobRight, phase: .down)
        case 5: return .key(control: .knobLeft, phase: .down)
        default: return nil
        }

        let isDown = plaintext[3] == 1
        return .key(control: control, phase: isDown ? .down : .up)
    }

    public static func parseDeviceNotice(plaintext: [UInt8]) -> VibeKeyNotice? {
        guard plaintext.count >= 2,
              (plaintext[0] & 0x1F) == 0x0B else {
            return nil
        }

        switch plaintext[1] {
        case 0x0D:
            guard plaintext.count >= 3 else { return nil }
            return .standby(isStandby: plaintext[2] != 0)
        case 0x0B:
            guard plaintext.count >= 3 else { return nil }
            return .active(isActive: (plaintext[2] & 0x01) != 0)
        case 0xF0:
            return .powerOn
        default:
            return nil
        }
    }

    public static func parseFirmwareVersion(plaintext: [UInt8]) -> String? {
        // Response format: header(0x01, 0x04, 0x04) + data
        guard plaintext.count >= 13,
              (plaintext[0] & 0x1F) == 0x01,
              plaintext[1] == 0x04,
              plaintext[2] == 0x04 else {
            return nil
        }
        let major = plaintext[10]
        let minor = plaintext[11]
        let patch = plaintext[12]
        return "\(major).\(minor).\(patch)"
    }

    public static func parseSerialNumberChunk(plaintext: [UInt8]) -> (seg: Int, text: String)? {
        // Response format: header(0x01, 0x01, 0x0B) + [len, seg, ascii...]
        guard plaintext.count >= 6,
              (plaintext[0] & 0x1F) == 0x01,
              plaintext[1] == 0x01,
              plaintext[2] == 0x0B else {
            return nil
        }
        let len = Int(plaintext[4])
        let seg = Int(plaintext[5])
        let end = min(6 + len, plaintext.count)
        guard 6 < end else { return nil }
        let chunkBytes = Array(plaintext[6..<end])
        let printable = chunkBytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
        guard printable, let str = String(bytes: chunkBytes, encoding: .ascii) else {
            return nil
        }
        return (seg, str)
    }

    public static func parsePowerResponse(plaintext: [UInt8]) -> VibeKeyPowerResponse? {
        guard plaintext.count >= 5,
              (plaintext[0] & 0x1F) == 0x01,
              plaintext[1] == 0x01,
              (plaintext[3] & 0x11) == 0x11 else {
            return nil
        }

        switch plaintext[2] {
        case 0x02: // Battery
            guard plaintext.count >= 11 else { return nil }
            let voltage = UInt16(plaintext[4]) | (UInt16(plaintext[5]) << 8)
            let percent = UInt16(plaintext[6]) | (UInt16(plaintext[7]) << 8)
            let isCharging = plaintext[10] != 0
            let isFullyCharged = plaintext.count >= 12 ? ((plaintext[11] & 0x08) != 0) : false
            return .battery(VibeKeyBatteryStatus(
                percent: min(percent, 100),
                voltageMillivolts: voltage,
                isCharging: isCharging,
                isFullyCharged: isFullyCharged
            ))

        case 0x2C: // Standby delay
            guard plaintext.count >= 8 else { return nil }
            let seconds = UInt32(plaintext[4])
                | (UInt32(plaintext[5]) << 8)
                | (UInt32(plaintext[6]) << 16)
                | (UInt32(plaintext[7]) << 24)
            return .standbyTime(seconds: seconds)

        case 0x42: // Sleep delay
            guard plaintext.count >= 8 else { return nil }
            let seconds = UInt32(plaintext[4])
                | (UInt32(plaintext[5]) << 8)
                | (UInt32(plaintext[6]) << 16)
                | (UInt32(plaintext[7]) << 24)
            return .sleepTime(seconds: seconds)

        case 0x90: // Mic Noise Reduction
            guard plaintext.count >= 5 else { return nil }
            return .micNR(level: plaintext[4])

        case 0x2A: // Mic Enable
            guard plaintext.count >= 5 else { return nil }
            return .micEnabled(plaintext[4] != 0)

        default:
            return nil
        }
    }
}
