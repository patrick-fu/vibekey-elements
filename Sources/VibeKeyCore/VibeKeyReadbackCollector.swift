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
/// testable presentation seam.
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
        statusSummary(language: VibeKeyLocalization.language)
    }

    public func statusSummary(language: VibeKeyLanguage) -> String {
        let strings = VibeKeyStrings(language: language)
        let powerState: String
        switch snapshot.isDeviceOn {
        case .some(false): powerState = strings[.stateDeviceOff]
        case .some(true): powerState = strings[.stateDeviceOn]
        case .none: powerState = strings[.stateDeviceLoading]
        }

        let loading = strings[.loading]
        let battery = snapshot.battery.map { strings.batteryValue($0) } ?? loading
        let micState = snapshot.micEnabled.map { strings[$0 ? .micShortOn : .micShortMuted] }

        let lines = [
            strings.labelValue(.labelStatus, "\(strings[.stateConnected]) · \(powerState)"),
            strings.labelValue(.labelBattery, battery),
            strings.labelValue(.labelFirmware, snapshot.firmwareVersion ?? loading),
            strings.labelValue(.labelSerial, snapshot.serialNumber ?? loading),
            strings.labelValue(.labelStandby, snapshot.standbyTimeSeconds.map { "\($0)s" } ?? loading),
            strings.labelValue(.labelDeepSleep, snapshot.sleepTimeSeconds.map { "\($0)s" } ?? loading),
            strings.labelValue(.labelNoiseReduction, snapshot.micNoiseReduction.map(String.init) ?? loading),
            strings.labelValue(.labelMicrophone, micState ?? loading)
        ]
        return lines.joined(separator: "\n")
    }

    /// "75% (Charging, 3700mV)" in the active language.
    public static func batteryValue(_ status: VibeKeyBatteryStatus) -> String {
        batteryValue(status, language: VibeKeyLocalization.language)
    }

    /// "75% (Charging, 3700mV)" in `language`.
    public static func batteryValue(_ status: VibeKeyBatteryStatus, language: VibeKeyLanguage) -> String {
        VibeKeyStrings(language: language).batteryValue(status)
    }

    public static func display(_ observation: VibeKeyReadbackObservation) -> String {
        display(observation, language: VibeKeyLocalization.language)
    }

    public static func display(_ observation: VibeKeyReadbackObservation, language: VibeKeyLanguage) -> String {
        let strings = VibeKeyStrings(language: language)
        switch observation {
        case .firmwareVersion(let version):
            return strings.labelValue(.labelFirmware, version)
        case .serialNumber(let serial):
            return strings.labelValue(.labelSerial, serial)
        case .power(let response):
            switch response {
            case .battery(let status): return strings.labelValue(.labelBattery, strings.batteryValue(status))
            case .standbyTime(let seconds): return strings.labelValue(.labelStandby, "\(seconds)s")
            case .sleepTime(let seconds): return strings.labelValue(.labelDeepSleep, "\(seconds)s")
            case .micNR(let level): return strings.labelValue(.labelNoiseReduction, String(level))
            case .micEnabled(let enabled): return strings[enabled ? .micOn : .micMuted]
            }
        case .notice(let notice):
            switch notice {
            case .standby(let isStandby): return strings[isStandby ? .stateDeviceStandby : .stateDeviceAwake]
            case .active(let isActive): return strings[isActive ? .stateDeviceOn : .stateDeviceOffReceiverConnected]
            case .powerOn: return strings[.stateDevicePoweredOn]
            }
        case .input(let control, let phase):
            switch control {
            case .knobLeft, .knobRight: return control.displayName(in: language)
            default: return "\(control.displayLabel) \(phase.rawValue)"
            }
        }
    }

    private var serialChunks: [Int: String] = [:]
}
