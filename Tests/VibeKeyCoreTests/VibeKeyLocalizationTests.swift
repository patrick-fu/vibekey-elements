import XCTest
@testable import VibeKeyCore

final class VibeKeyLocalizationTests: XCTestCase {
    // MARK: - Language resolution

    func testResolvesSupportedLanguagesFromSystemPreferences() {
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["fr-FR", "en-US"]), .french)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["fr-CA"]), .french)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["en-GB"]), .english)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
    }

    func testFallsBackToNextPreferenceThenEnglish() {
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["de-DE", "fr-FR"]), .french)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["de-DE"]), .english)
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: []), .english)
    }

    func testEnvironmentOverrideWinsOverSystemPreferences() {
        let env = [VibeKeyLocalization.environmentKey: "fr"]
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["en-US"], environment: env), .french)
        let english = [VibeKeyLocalization.environmentKey: "en"]
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["fr-FR"], environment: english), .english)
    }

    func testUnsupportedEnvironmentOverrideIsIgnored() {
        let env = [VibeKeyLocalization.environmentKey: "de"]
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["fr-FR"], environment: env), .french)
        let empty = [VibeKeyLocalization.environmentKey: ""]
        XCTAssertEqual(VibeKeyLocalization.resolve(preferredLanguages: ["fr-FR"], environment: empty), .french)
    }

    // MARK: - Table integrity

    func testEveryStaticTranslationIsNonEmpty() {
        for language in VibeKeyLanguage.allCases {
            let strings = VibeKeyStrings(language: language)
            for key in L10nKey.allCases {
                XCTAssertFalse(
                    strings[key].trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(language.rawValue).\(key.rawValue) is empty"
                )
            }
        }
    }

    func testFrenchAndEnglishAreActuallyTranslated() {
        // Catches copy-paste of the English table into French for UI-visible keys.
        let shared: Set<L10nKey> = [
            .deviceName, .listSeparator, .labelFirmware, .labelMicrophone, .menuMicrophone,
            .presetVolumeUp, .presetVolumeDown, .standby15Min, .sleep30Min
        ]
        let english = VibeKeyStrings(language: .english)
        let french = VibeKeyStrings(language: .french)
        for key in L10nKey.allCases where !shared.contains(key) {
            XCTAssertNotEqual(
                english[key],
                french[key],
                "fr.\(key.rawValue) is identical to English"
            )
        }
    }

    // MARK: - Type-safe parameterized strings

    func testTypedParameterizedStringsAcrossLanguages() {
        let en = VibeKeyStrings(language: .english)
        let fr = VibeKeyStrings(language: .french)
        let zh = VibeKeyStrings(language: .simplifiedChinese)

        XCTAssertEqual(en.labelValue("Status", "Connected"), "Status: Connected")
        XCTAssertEqual(fr.labelValue("État", "Connecté"), "État\u{202F}: Connecté")
        XCTAssertEqual(zh.labelValue("状态", "已连接"), "状态: 已连接")

        XCTAssertEqual(en.batteryValue(percent: 75, state: "Charging", voltageMillivolts: 3700), "75% (Charging, 3700mV)")
        XCTAssertEqual(fr.batteryValue(percent: 75, state: "En charge", voltageMillivolts: 3700), "75\u{202F}% (En charge, 3700\u{202F}mV)")
        XCTAssertEqual(zh.batteryValue(percent: 75, state: "充电中", voltageMillivolts: 3700), "75% (充电中, 3700mV)")

        XCTAssertEqual(
            en.permissionTooltipMissing(usage: "Reads events", permissionName: "Input Monitoring"),
            "Reads events. Click to open Input Monitoring settings."
        )
        XCTAssertEqual(
            fr.permissionTooltipMissing(usage: "Lit les touches", permissionName: "Surveillance de l’entrée"),
            "Lit les touches. Cliquez pour ouvrir les réglages «\u{00A0}Surveillance de l’entrée\u{00A0}»."
        )
        XCTAssertEqual(
            zh.permissionMissing(["输入监控", "辅助功能"]),
            "○ 系统权限：输入监控、辅助功能待授权"
        )
        XCTAssertEqual(en.mappingCustomCurrent("⌘C"), "Custom: ⌘C")
        XCTAssertEqual(fr.mappingCustomCurrent("⌘C"), "Personnalisé\u{202F}: ⌘C")
        XCTAssertEqual(fr.customTitle("Touche haut (K1)"), "Personnaliser «\u{00A0}Touche haut (K1)\u{00A0}»")
        XCTAssertEqual(en.customTitle("Top button (K1)", isLongPress: true), "Customize Top button (K1) (Long Press)")
        XCTAssertEqual(fr.customTitle("Touche haut (K1)", isLongPress: true), "Personnaliser «\u{00A0}Touche haut (K1)\u{00A0}» (appui long)")
        XCTAssertEqual(zh.customTitle("上键 (K1)", isLongPress: true), "自定义 上键 (K1)（长按）")
        XCTAssertEqual(en.longPressFlashLabel("K1"), "K1+")
        XCTAssertEqual(zh.longPressFlashLabel("K1"), "K1长")
        XCTAssertEqual(en.menuFirmwareVersion("1.2.0"), "Firmware version: 1.2.0")
        XCTAssertEqual(fr.menuSerialNumber("VK-05A"), "Numéro de série\u{202F}: VK-05A")
    }

    // MARK: - Explicit-language Core models & readback (no global state mutation)

    func testCoreDisplayNamesFollowExplicitLanguage() {
        XCTAssertEqual(InputControl.knobLeft.displayName(in: .english), "Knob turn left")
        XCTAssertEqual(LEDMode.breathing.displayName(in: .english), "Breathing")
        XCTAssertEqual(PresetAction.none.displayName(in: .english), "No action")
        XCTAssertEqual(VibeKeyPermission.accessibility.settingsTitle(in: .english), "Accessibility Settings…")
        XCTAssertEqual(VibeKeyPermissionReport(permission: .accessibility, status: .denied).statusTitle(in: .english), "Denied")

        XCTAssertEqual(InputControl.knobLeft.displayName(in: .french), "Molette vers la gauche")
        XCTAssertEqual(LEDMode.breathing.displayName(in: .french), "Respiration")
        XCTAssertEqual(PresetAction.none.displayName(in: .french), "Aucune action")
        XCTAssertEqual(VibeKeyPermission.accessibility.settingsTitle(in: .french), "Réglages «\u{00A0}Accessibilité\u{00A0}»…")
        XCTAssertEqual(VibeKeyPermissionReport(permission: .accessibility, status: .denied).statusTitle(in: .french), "Refusé")
    }

    func testReadbackSummaryInEnglishAndFrench() throws {
        var collector = VibeKeyReadbackCollector()
        XCTAssertNotNil(collector.ingest(plaintext: [0x0B, 0x0B, 0x00]))

        let englishSummary = collector.statusSummary(language: .english)
        XCTAssertTrue(englishSummary.contains("Status: Connected · Device off"), englishSummary)
        XCTAssertTrue(englishSummary.contains("Firmware: Loading…"), englishSummary)

        let frenchSummary = collector.statusSummary(language: .french)
        XCTAssertTrue(frenchSummary.contains("État\u{202F}: Connecté · Appareil éteint"), frenchSummary)
        XCTAssertTrue(frenchSummary.contains("Firmware\u{202F}: Lecture…"), frenchSummary)
    }
}
