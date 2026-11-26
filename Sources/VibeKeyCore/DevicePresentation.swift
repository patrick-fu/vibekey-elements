import Foundation

/// Single source of truth for hardware option tables shared across the
/// settings popover and status-bar context menu.
public enum VibeKeyHardwareOptions {
    public struct NoiseReductionOption: Equatable, Sendable {
        public let level: UInt8
        public let fullTitleKey: L10nKey
        public let shortTitleKey: L10nKey

        public init(level: UInt8, fullTitleKey: L10nKey, shortTitleKey: L10nKey) {
            self.level = level
            self.fullTitleKey = fullTitleKey
            self.shortTitleKey = shortTitleKey
        }
    }

    public struct TimeoutOption: Equatable, Sendable {
        public let seconds: UInt32
        public let titleKey: L10nKey

        public init(seconds: UInt32, titleKey: L10nKey) {
            self.seconds = seconds
            self.titleKey = titleKey
        }
    }

    public static let noiseReductionLevels: [NoiseReductionOption] = [
        NoiseReductionOption(level: 0, fullTitleKey: .noiseLevel0, shortTitleKey: .noiseShort0),
        NoiseReductionOption(level: 1, fullTitleKey: .noiseLevel1, shortTitleKey: .noiseShort1),
        NoiseReductionOption(level: 2, fullTitleKey: .noiseLevel2, shortTitleKey: .noiseShort2),
        NoiseReductionOption(level: 3, fullTitleKey: .noiseLevel3, shortTitleKey: .noiseShort3)
    ]

    public static let standbyOptions: [TimeoutOption] = [
        TimeoutOption(seconds: 300, titleKey: .standby5Min),
        TimeoutOption(seconds: 900, titleKey: .standby15Min),
        TimeoutOption(seconds: 1800, titleKey: .standby30Min),
        TimeoutOption(seconds: 0, titleKey: .standbyNever)
    ]

    public static let sleepOptions: [TimeoutOption] = [
        TimeoutOption(seconds: 1800, titleKey: .sleep30Min),
        TimeoutOption(seconds: 3600, titleKey: .sleep1Hour),
        TimeoutOption(seconds: 7200, titleKey: .sleep2Hours),
        TimeoutOption(seconds: 14400, titleKey: .sleep4Hours)
    ]
}

/// Pure, localized presentation state for the menu-bar item, settings popover
/// header, and context-menu header. Consolidates connection, power-saving,
/// standby, battery, and firmware formatting in one testable module.
public struct VibeKeyDevicePresentation: Equatable, Sendable {
    public enum StatusTone: Equatable, Sendable {
        case connected
        case powerSaving
        case inactive
    }

    public let statusItemSymbolName: String
    public let statusItemText: String
    public let statusItemIsMuted: Bool
    public let statusItemToolTip: String

    public let panelStatusText: String
    public let panelStatusTone: StatusTone
    public let panelHardwareInfoText: String

    public let menuStatusTitle: String
    public let menuFirmwareTitle: String?
    public let menuSerialTitle: String?
    public let menuBatteryTitle: String?

    public init(
        snapshot: VibeKeyDeviceInfoSnapshot,
        isLocalPowerSaving: Bool,
        strings: VibeKeyStrings = .current
    ) {
        let device = strings[.deviceName]

        // 1. Status bar item
        if !snapshot.isConnected || isLocalPowerSaving {
            self.statusItemSymbolName = "dial.medium"
        } else {
            self.statusItemSymbolName = "dial.medium.fill"
        }

        if !snapshot.isConnected {
            self.statusItemText = ""
            self.statusItemIsMuted = false
            self.statusItemToolTip = "\(device) (\(strings[.stateNotConnected]))"
        } else if snapshot.isDeviceOn == false {
            self.statusItemText = " OFF"
            self.statusItemIsMuted = true
            self.statusItemToolTip = "\(device) · \(strings[.stateConnected]) · \(strings[.stateDeviceOff])"
        } else if let battery = snapshot.battery {
            let bolt = battery.isCharging ? " ⚡" : ""
            let standbyMarker = isLocalPowerSaving ? " 💤" : ""
            self.statusItemText = " \(battery.percent)%\(bolt)\(standbyMarker)"
            self.statusItemIsMuted = false
            let chargeState = battery.isCharging
                ? strings[.charging]
                : strings[isLocalPowerSaving ? .statePowerSaving : .onBattery]
            let batteryValue = strings.batteryValue(
                percent: battery.percent,
                state: chargeState,
                voltageMillivolts: battery.voltageMillivolts
            )
            self.statusItemToolTip = "\(device) · \(strings.labelValue(.labelBattery, batteryValue))"
        } else {
            self.statusItemText = ""
            self.statusItemIsMuted = false
            self.statusItemToolTip = "\(device) (\(strings[isLocalPowerSaving ? .statePowerSaving : .stateConnected]))"
        }

        // 2. Popover header
        if snapshot.isConnected {
            let batteryText: String
            if let battery = snapshot.battery {
                let charging = battery.isCharging ? " ⚡(\(strings[.charging]))" : ""
                batteryText = " · \(strings[.labelBattery]) \(battery.percent)%\(charging) [\(battery.voltageMillivolts)mV]"
            } else {
                batteryText = " · \(strings[.panelBatteryLoading])"
            }

            func firmwareLine(fallback: L10nKey) -> String {
                let fw = snapshot.firmwareVersion ?? strings[fallback]
                let sn = snapshot.serialNumber ?? strings[fallback]
                return "\(strings.labelValue(.labelFirmware, fw))  |  SN: \(sn)"
            }

            if snapshot.isDeviceOn == false {
                self.panelStatusText = "● \(device) (\(strings[.stateConnected]) · \(strings[.stateDeviceOff]))"
                self.panelStatusTone = .inactive
                self.panelHardwareInfoText = "\(firmwareLine(fallback: .unknown))  |  \(strings[.panelBatteryCached])"
            } else if isLocalPowerSaving {
                self.panelStatusText = "● \(device) (\(strings[.statePowerSaving]))\(batteryText)"
                self.panelStatusTone = .powerSaving
                self.panelHardwareInfoText = "\(firmwareLine(fallback: .loading)) \(strings[.panelPressToWake])"
            } else if snapshot.isStandby {
                self.panelStatusText = "● \(device) (\(strings[.stateConnected]) · \(strings[.stateHardwareStandby]))\(batteryText)"
                self.panelStatusTone = .connected
                self.panelHardwareInfoText = firmwareLine(fallback: .loading)
            } else {
                self.panelStatusText = "● \(device) (\(strings[.stateConnected]))\(batteryText)"
                self.panelStatusTone = .connected
                self.panelHardwareInfoText = firmwareLine(fallback: .loading)
            }
        } else {
            self.panelStatusText = "○ \(strings[.panelNotConnected])"
            self.panelStatusTone = .inactive
            self.panelHardwareInfoText = strings[.panelPlugIn]
        }

        // 3. Context menu header
        if !snapshot.isConnected {
            self.menuStatusTitle = "\(device) (\(strings[.stateOffline]))"
        } else if snapshot.isDeviceOn == false {
            self.menuStatusTitle = "\(device) (\(strings[.stateConnected]) · \(strings[.stateDeviceOff]))"
        } else {
            self.menuStatusTitle = "\(device) (\(strings[.stateConnected]))"
        }

        self.menuFirmwareTitle = snapshot.firmwareVersion.map { strings.menuFirmwareVersion($0) }
        self.menuSerialTitle = snapshot.serialNumber.map { strings.menuSerialNumber($0) }
        self.menuBatteryTitle = snapshot.battery.map { battery in
            let title = strings.labelValue(.labelBattery, strings.batteryValue(battery))
            return battery.isCharging ? "⚡ \(title)" : title
        }
    }
}
