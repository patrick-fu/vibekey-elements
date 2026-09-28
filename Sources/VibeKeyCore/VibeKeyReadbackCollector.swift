import Foundation

public enum VibeKeyReadbackObservation: Equatable, Sendable {
    case firmwareVersion(String)
    case serialNumber(String)
    case power(VibeKeyPowerResponse)
    case notice(VibeKeyNotice)
    case input(InputControl, ButtonPhase)
}

/// Collects decrypted HID responses for CLI readback and live monitoring.
/// This keeps the stateless packet parsers reusable while giving the CLI a
/// testable presentation boundary.
public struct VibeKeyReadbackCollector: Sendable {
    public private(set) var snapshot = VibeKeyDeviceInfoSnapshot(isConnected: true)

    public init() {}

    public var isQueryStatusComplete: Bool {
        snapshot.firmwareVersion != nil
            && snapshot.serialNumber != nil
            && snapshot.battery != nil
            && snapshot.standbyTimeSeconds != nil
            && snapshot.sleepTimeSeconds != nil
            && snapshot.micNoiseReduction != nil
            && snapshot.micEnabled != nil
    }

    @discardableResult
    public mutating func ingest(plaintext: [UInt8]) -> VibeKeyReadbackObservation? {
        if let version = VibeKeyParser.parseFirmwareVersion(plaintext: plaintext) {
            snapshot.firmwareVersion = version
            return .firmwareVersion(version)
        }

        if let chunk = VibeKeyParser.parseSerialNumberChunk(plaintext: plaintext) {
            serialChunks[chunk.seg] = chunk.text
            let serial = serialChunks.keys.sorted().compactMap { serialChunks[$0] }.joined()
            if !serial.isEmpty {
                snapshot.serialNumber = serial
                return .serialNumber(serial)
            }
            return nil
        }

        if let event = VibeKeyParser.parseDeviceEvent(plaintext: plaintext),
           case let .key(control, phase) = event {
            return .input(control, phase)
        }

        if let notice = VibeKeyParser.parseDeviceNotice(plaintext: plaintext) {
            switch notice {
            case let .active(isActive):
                snapshot.isDeviceOn = isActive
                snapshot.isConnected = true
            case .powerOn:
                snapshot.isDeviceOn = true
                snapshot.isConnected = true
            case .standby(let isStandby):
                snapshot.isStandby = isStandby
            }
            return .notice(notice)
        }

        if let power = VibeKeyParser.parsePowerResponse(plaintext: plaintext) {
            switch power {
            case .battery(let status):
                snapshot.battery = status
            case .standbyTime(let seconds):
                snapshot.standbyTimeSeconds = seconds
            case .sleepTime(let seconds):
                snapshot.sleepTimeSeconds = seconds
            case .micNR(let level):
                snapshot.micNoiseReduction = level
            case .micEnabled(let enabled):
                snapshot.micEnabled = enabled
            }
            return .power(power)
        }

        return nil
    }

    public func statusSummary() -> String {
        let powerState: String
        switch snapshot.isDeviceOn {
        case .some(false): powerState = "设备关机"
        case .some(true): powerState = "设备开机"
        case .none: powerState = "设备状态获取中"
        }

        let battery: String
        if let value = snapshot.battery {
            let charging = value.isCharging ? "充电中" : "电池供电"
            battery = "电量: \(value.percent)% (\(charging), \(value.voltageMillivolts)mV)"
        } else {
            battery = "电量: 获取中"
        }

        let lines = [
            "状态: 已连接 · \(powerState)",
            battery,
            "固件: \(snapshot.firmwareVersion ?? "获取中")",
            "序列号: \(snapshot.serialNumber ?? "获取中")",
            "待机: \(snapshot.standbyTimeSeconds.map { "\($0)s" } ?? "获取中")",
            "深度休眠: \(snapshot.sleepTimeSeconds.map { "\($0)s" } ?? "获取中")",
            "麦克风降噪: \(snapshot.micNoiseReduction.map(String.init) ?? "获取中")",
            "麦克风: \(snapshot.micEnabled.map { $0 ? "开启" : "静音" } ?? "获取中")"
        ]
        return lines.joined(separator: "\n")
    }

    public static func display(_ observation: VibeKeyReadbackObservation) -> String {
        switch observation {
        case .firmwareVersion(let version):
            return "固件 \(version)"
        case .serialNumber(let serial):
            return "序列号 \(serial)"
        case .power(let response):
            switch response {
            case .battery(let status):
                let charging = status.isCharging ? "充电中" : "电池供电"
                return "电量 \(status.percent)% (\(charging), \(status.voltageMillivolts)mV)"
            case .standbyTime(let seconds): return "待机时间 \(seconds)s"
            case .sleepTime(let seconds): return "深度休眠时间 \(seconds)s"
            case .micNR(let level): return "麦克风降噪 \(level)"
            case .micEnabled(let enabled): return enabled ? "麦克风开启" : "麦克风静音"
            }
        case .notice(let notice):
            switch notice {
            case .standby(let isStandby): return isStandby ? "设备待机" : "设备唤醒"
            case .active(let isActive): return isActive ? "设备开机" : "设备关机（接收器仍连接）"
            case .powerOn: return "设备上电"
            }
        case .input(let control, let phase):
            switch control {
            case .knobLeft: return "旋钮左旋"
            case .knobRight: return "旋钮右旋"
            default: return "\(control.displayLabel) \(phase.rawValue)"
            }
        }
    }

    private var serialChunks: [Int: String] = [:]
}
