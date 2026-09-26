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

    public static func setStandbyTimeoutReport(seconds: UInt32) throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x01
        plaintext[2] = 0x2C
        plaintext[3] = 0x04
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
        plaintext[3] = 0x04
        plaintext[4] = UInt8(truncatingIfNeeded: seconds)
        plaintext[5] = UInt8(truncatingIfNeeded: seconds >> 8)
        plaintext[6] = UInt8(truncatingIfNeeded: seconds >> 16)
        plaintext[7] = UInt8(truncatingIfNeeded: seconds >> 24)
        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func setLEDReport(channel: UInt8, mode: LEDMode, brightness: UInt8) throws -> [UInt8] {
        guard channel <= 3 else {
            throw VibeKeyProtocolError.invalidChannel(channel)
        }

        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x88
        plaintext[3] = 0x04

        let fieldMask: UInt8
        switch mode {
        case .solid:
            fieldMask = 0x40 // always-on brightness
            plaintext[4] = fieldMask
            plaintext[5] = channel
            plaintext[12 + Int(channel) * 5] = brightness
        case .breathing:
            fieldMask = 0x30 // breathing level & brightness
            plaintext[4] = fieldMask
            plaintext[5] = channel
            plaintext[10 + Int(channel) * 5] = 0x02 // level
            plaintext[11 + Int(channel) * 5] = brightness
        case .off:
            fieldMask = 0x40
            plaintext[4] = fieldMask
            plaintext[5] = channel
            plaintext[12 + Int(channel) * 5] = 0x00
        case .auto:
            return try resetLEDReport()
        }

        return try TEACodec.buildOutputReport(encrypting: plaintext)
    }

    public static func resetLEDReport() throws -> [UInt8] {
        var plaintext = [UInt8](repeating: 0, count: VibeKeyDeviceInfo.packetLength)
        plaintext[0] = 0x01
        plaintext[1] = 0x0B
        plaintext[2] = 0x88
        plaintext[3] = 0x04
        plaintext[4] = 0x01 // Reset to global mode
        plaintext[6] = 0x00
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
        plaintext[1] = 0x0B
        plaintext[2] = 0x8A
        plaintext[3] = 0x04
        plaintext[4] = level
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
            return .battery(VibeKeyBatteryStatus(
                percent: min(percent, 100),
                voltageMillivolts: voltage,
                isCharging: isCharging
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

        default:
            return nil
        }
    }
}
