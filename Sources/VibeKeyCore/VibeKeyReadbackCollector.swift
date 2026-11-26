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
        case .some(false): powerState = tr(.stateDeviceOff)
        case .some(true): powerState = tr(.stateDeviceOn)
        case .none: powerState = tr(.stateDeviceLoading)
        }

        let loading = tr(.loading)
        let battery = snapshot.battery.map(Self.batteryValue) ?? loading
        let micState = snapshot.micEnabled.map { tr($0 ? .micShortOn : .micShortMuted) }

        let lines = [
            tr(.labelValue, tr(.labelStatus), "\(tr(.stateConnected)) · \(powerState)"),
            tr(.labelValue, tr(.labelBattery), battery),
            tr(.labelValue, tr(.labelFirmware), snapshot.firmwareVersion ?? loading),
            tr(.labelValue, tr(.labelSerial), snapshot.serialNumber ?? loading),
            tr(.labelValue, tr(.labelStandby), snapshot.standbyTimeSeconds.map { "\($0)s" } ?? loading),
            tr(.labelValue, tr(.labelDeepSleep), snapshot.sleepTimeSeconds.map { "\($0)s" } ?? loading),
            tr(.labelValue, tr(.labelNoiseReduction), snapshot.micNoiseReduction.map(String.init) ?? loading),
            tr(.labelValue, tr(.labelMicrophone), micState ?? loading)
        ]
        return lines.joined(separator: "\n")
    }

    /// "75% (Charging, 3700mV)" in the active language.
    public static func batteryValue(_ status: VibeKeyBatteryStatus) -> String {
        tr(.batteryValue, status.percent, tr(status.isCharging ? .charging : .onBattery), status.voltageMillivolts)
    }

    public static func display(_ observation: VibeKeyReadbackObservation) -> String {
        switch observation {
        case .firmwareVersion(let version):
            return tr(.labelValue, tr(.labelFirmware), version)
        case .serialNumber(let serial):
            return tr(.labelValue, tr(.labelSerial), serial)
        case .power(let response):
            switch response {
            case .battery(let status): return tr(.labelValue, tr(.labelBattery), batteryValue(status))
            case .standbyTime(let seconds): return tr(.labelValue, tr(.labelStandby), "\(seconds)s")
            case .sleepTime(let seconds): return tr(.labelValue, tr(.labelDeepSleep), "\(seconds)s")
            case .micNR(let level): return tr(.labelValue, tr(.labelNoiseReduction), level)
            case .micEnabled(let enabled): return tr(enabled ? .micOn : .micMuted)
            }
        case .notice(let notice):
            switch notice {
            case .standby(let isStandby): return tr(isStandby ? .stateDeviceStandby : .stateDeviceAwake)
            case .active(let isActive): return tr(isActive ? .stateDeviceOn : .stateDeviceOffReceiverConnected)
            case .powerOn: return tr(.stateDevicePoweredOn)
            }
        case .input(let control, let phase):
            switch control {
            case .knobLeft, .knobRight: return control.displayName
            default: return "\(control.displayLabel) \(phase.rawValue)"
            }
        }
    }

    private var serialChunks: [Int: String] = [:]
}
