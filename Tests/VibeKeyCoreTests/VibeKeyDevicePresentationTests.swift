import XCTest
@testable import VibeKeyCore

final class VibeKeyDevicePresentationTests: XCTestCase {
    func testDisconnectedPresentationAcrossLanguages() {
        let snapshot = VibeKeyDeviceInfoSnapshot(isConnected: false)

        let en = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: false, strings: VibeKeyStrings(language: .english))
        XCTAssertEqual(en.statusItemSymbolName, "dial.medium")
        XCTAssertEqual(en.statusItemText, "")
        XCTAssertEqual(en.statusItemToolTip, "Ulanzi AU05 (Not connected)")
        XCTAssertEqual(en.panelStatusText, "○ Device not connected")
        XCTAssertEqual(en.panelStatusTone, .inactive)
        XCTAssertEqual(en.panelHardwareInfoText, "Plug in the 2.4 GHz receiver or connect via USB")
        XCTAssertEqual(en.menuStatusTitle, "Ulanzi AU05 (Offline)")
        XCTAssertNil(en.menuFirmwareTitle)
        XCTAssertNil(en.menuSerialTitle)
        XCTAssertNil(en.menuBatteryTitle)

        let fr = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: false, strings: VibeKeyStrings(language: .french))
        XCTAssertEqual(fr.statusItemToolTip, "Ulanzi AU05 (Non connecté)")
        XCTAssertEqual(fr.panelStatusText, "○ Appareil non connecté")
        XCTAssertEqual(fr.menuStatusTitle, "Ulanzi AU05 (Hors ligne)")
    }

    func testConnectedChargingPresentation() {
        let snapshot = VibeKeyDeviceInfoSnapshot(
            isConnected: true,
            firmwareVersion: "4.6.3",
            serialNumber: "VK-05A",
            battery: VibeKeyBatteryStatus(percent: 82, voltageMillivolts: 4050, isCharging: true),
            isDeviceOn: true
        )

        let zh = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: false, strings: VibeKeyStrings(language: .simplifiedChinese))
        XCTAssertEqual(zh.statusItemSymbolName, "dial.medium.fill")
        XCTAssertEqual(zh.statusItemText, " 82% ⚡")
        XCTAssertFalse(zh.statusItemIsMuted)
        XCTAssertEqual(zh.statusItemToolTip, "优篮子 AU05 · 电量: 82% (充电中, 4050mV)")
        XCTAssertEqual(zh.panelStatusTone, .connected)
        XCTAssertTrue(zh.panelStatusText.contains("⚡(充电中)"), zh.panelStatusText)
        XCTAssertEqual(zh.panelHardwareInfoText, "固件: 4.6.3  |  SN: VK-05A")
        XCTAssertEqual(zh.menuFirmwareTitle, "固件版本: 4.6.3")
        XCTAssertEqual(zh.menuSerialTitle, "序列号: VK-05A")
        XCTAssertEqual(zh.menuBatteryTitle, "⚡ 电量: 82% (充电中, 4050mV)")
    }

    func testDevicePoweredOffPresentation() {
        let snapshot = VibeKeyDeviceInfoSnapshot(
            isConnected: true,
            firmwareVersion: nil,
            serialNumber: nil,
            battery: VibeKeyBatteryStatus(percent: 60, voltageMillivolts: 3800, isCharging: false),
            isDeviceOn: false
        )

        let en = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: false, strings: VibeKeyStrings(language: .english))
        XCTAssertEqual(en.statusItemText, " OFF")
        XCTAssertTrue(en.statusItemIsMuted)
        XCTAssertEqual(en.statusItemToolTip, "Ulanzi AU05 · Connected · Device off")
        XCTAssertEqual(en.panelStatusTone, .inactive)
        XCTAssertTrue(en.panelHardwareInfoText.contains("Unknown"), en.panelHardwareInfoText)
        XCTAssertTrue(en.panelHardwareInfoText.contains("Battery: last known value"), en.panelHardwareInfoText)
        XCTAssertEqual(en.menuStatusTitle, "Ulanzi AU05 (Connected · Device off)")
    }

    func testLocalPowerSavingAndHardwareStandbyPresentations() {
        let snapshot = VibeKeyDeviceInfoSnapshot(
            isConnected: true,
            firmwareVersion: "4.6.3",
            serialNumber: "VK-05A",
            battery: VibeKeyBatteryStatus(percent: 50, voltageMillivolts: 3750, isCharging: false),
            isStandby: true,
            isDeviceOn: true
        )

        let powerSaving = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: true, strings: VibeKeyStrings(language: .english))
        XCTAssertEqual(powerSaving.statusItemSymbolName, "dial.medium")
        XCTAssertEqual(powerSaving.statusItemText, " 50% 💤")
        XCTAssertEqual(powerSaving.statusItemToolTip, "Ulanzi AU05 · Battery: 50% (Power saving, 3750mV)")
        XCTAssertEqual(powerSaving.panelStatusTone, .powerSaving)
        XCTAssertTrue(powerSaving.panelHardwareInfoText.contains("(press any key to wake)"), powerSaving.panelHardwareInfoText)

        let hardwareStandby = VibeKeyDevicePresentation(snapshot: snapshot, isLocalPowerSaving: false, strings: VibeKeyStrings(language: .french))
        XCTAssertEqual(hardwareStandby.statusItemSymbolName, "dial.medium.fill")
        XCTAssertEqual(hardwareStandby.panelStatusTone, .connected)
        XCTAssertTrue(hardwareStandby.panelStatusText.contains("Veille matérielle"), hardwareStandby.panelStatusText)
    }

    func testConfigurationResetHelpersPreserveUnrelatedSettings() {
        let custom = VibeKeyConfiguration(
            topButton: .shellCommand(command: "echo hi"),
            middleButton: .keySequence(keys: ["command", "c"]),
            bottomButton: .keySequence(keys: ["command", "v"]),
            knobLeft: .keySequence(keys: ["f1"]),
            knobRight: .keySequence(keys: ["f2"]),
            knobPress: .keySequence(keys: ["f3"]),
            micNoiseReduction: 3,
            micEnabled: false,
            ledMode: .breathing,
            standbySeconds: 1800,
            sleepSeconds: 7200,
            longConnectedMode: true,
            topButtonLongPress: .keySequence(keys: ["fn"]),
            knobPressLongPress: .shellCommand(command: "open -a Terminal")
        )

        let keysReset = custom.resettingKeyMappingsToDefaults()
        let defaults = VibeKeyConfiguration()
        XCTAssertEqual(keysReset.topButton, defaults.topButton)
        XCTAssertEqual(keysReset.knobPress, defaults.knobPress)
        XCTAssertNil(keysReset.topButtonLongPress)
        XCTAssertNil(keysReset.knobPressLongPress)
        XCTAssertEqual(keysReset.micNoiseReduction, 3)
        XCTAssertEqual(keysReset.micEnabled, false)
        XCTAssertEqual(keysReset.ledMode, .breathing)
        XCTAssertEqual(keysReset.standbySeconds, 1800)
        XCTAssertEqual(keysReset.sleepSeconds, 7200)
        XCTAssertEqual(keysReset.longConnectedMode, true)

        let hwReset = custom.resettingHardwareSettingsToDefaults()
        XCTAssertEqual(hwReset.topButton, custom.topButton)
        XCTAssertEqual(hwReset.knobPress, custom.knobPress)
        XCTAssertEqual(hwReset.topButtonLongPress, custom.topButtonLongPress)
        XCTAssertEqual(hwReset.knobPressLongPress, custom.knobPressLongPress)
        XCTAssertEqual(hwReset.longConnectedMode, true)
        XCTAssertEqual(hwReset.micNoiseReduction, defaults.micNoiseReduction)
        XCTAssertEqual(hwReset.micEnabled, defaults.micEnabled)
        XCTAssertEqual(hwReset.ledMode, defaults.ledMode)
        XCTAssertEqual(hwReset.standbySeconds, defaults.standbySeconds)
        XCTAssertEqual(hwReset.sleepSeconds, defaults.sleepSeconds)
    }

    func testHardwareOptionsCoverExpectedValues() {
        XCTAssertEqual(VibeKeyHardwareOptions.noiseReductionLevels.map(\.level), [0, 1, 2, 3])
        XCTAssertEqual(VibeKeyHardwareOptions.standbyOptions.map(\.seconds), [300, 900, 1800, 0])
        XCTAssertEqual(VibeKeyHardwareOptions.sleepOptions.map(\.seconds), [1800, 3600, 7200, 14400])
    }
}
