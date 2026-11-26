import XCTest
@testable import VibeKeyCore

final class VibeKeyLocalizationTests: XCTestCase {
    private var previousLanguage: VibeKeyLanguage!

    override func setUp() {
        super.setUp()
        previousLanguage = VibeKeyLocalization.language
    }

    override func tearDown() {
        VibeKeyLocalization.language = previousLanguage
        super.tearDown()
    }

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

    func testEveryTranslationIsNonEmpty() {
        for language in VibeKeyLanguage.allCases {
            for key in L10nKey.allCases {
                XCTAssertFalse(
                    VibeKeyLocalization.template(key, language: language).trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(language.rawValue).\(key.rawValue) is empty"
                )
            }
        }
    }

    /// A translation must consume exactly the same arguments as English,
    /// otherwise String(format:) reads garbage or drops values.
    func testFormatPlaceholdersMatchEnglish() {
        for key in L10nKey.allCases {
            let reference = placeholders(in: VibeKeyLocalization.template(key, language: .english))
            for language in VibeKeyLanguage.allCases where language != .english {
                XCTAssertEqual(
                    placeholders(in: VibeKeyLocalization.template(key, language: language)),
                    reference,
                    "\(language.rawValue).\(key.rawValue) placeholders differ from English"
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
        for key in L10nKey.allCases where !shared.contains(key) {
            XCTAssertNotEqual(
                VibeKeyLocalization.template(key, language: .english),
                VibeKeyLocalization.template(key, language: .french),
                "fr.\(key.rawValue) is identical to English"
            )
        }
    }

    // MARK: - Rendered output

    func testFormattingFillsPositionalArguments() {
        XCTAssertEqual(
            VibeKeyLocalization.string(.batteryValue, 75, "Charging", 3700, language: .english),
            "75% (Charging, 3700mV)"
        )
        XCTAssertEqual(
            VibeKeyLocalization.string(.batteryValue, 75, "En charge", 3700, language: .french),
            "75\u{202F}% (En charge, 3700\u{202F}mV)"
        )
        XCTAssertEqual(
            VibeKeyLocalization.string(.permissionTooltipMissing, "Reads events", "Input Monitoring", language: .english),
            "Reads events. Click to open Input Monitoring settings."
        )
    }

    func testCoreDisplayNamesFollowActiveLanguage() {
        VibeKeyLocalization.language = .english
        XCTAssertEqual(InputControl.knobLeft.displayName, "Knob turn left")
        XCTAssertEqual(LEDMode.breathing.displayName, "Breathing")
        XCTAssertEqual(PresetAction.none.displayName, "No action")
        XCTAssertEqual(VibeKeyPermission.accessibility.settingsTitle, "Accessibility Settings…")
        XCTAssertEqual(VibeKeyPermissionReport(permission: .accessibility, status: .denied).statusTitle, "Denied")

        VibeKeyLocalization.language = .french
        XCTAssertEqual(InputControl.knobLeft.displayName, "Molette vers la gauche")
        XCTAssertEqual(LEDMode.breathing.displayName, "Respiration")
        XCTAssertEqual(PresetAction.none.displayName, "Aucune action")
        XCTAssertEqual(VibeKeyPermission.accessibility.settingsTitle, "Réglages «\u{00A0}Accessibilité\u{00A0}»…")
        XCTAssertEqual(VibeKeyPermissionReport(permission: .accessibility, status: .denied).statusTitle, "Refusé")
    }

    func testReadbackSummaryInEnglishAndFrench() throws {
        var collector = VibeKeyReadbackCollector()
        // Power-off notice, then battery 75% charging at 3700mV.
        XCTAssertNotNil(collector.ingest(plaintext: [0x0B, 0x0B, 0x00]))

        VibeKeyLocalization.language = .english
        var summary = collector.statusSummary()
        XCTAssertTrue(summary.contains("Status: Connected · Device off"), summary)
        XCTAssertTrue(summary.contains("Firmware: Loading…"), summary)

        VibeKeyLocalization.language = .french
        summary = collector.statusSummary()
        XCTAssertTrue(summary.contains("État\u{202F}: Connecté · Appareil éteint"), summary)
        XCTAssertTrue(summary.contains("Firmware\u{202F}: Lecture…"), summary)
    }

    private func placeholders(in template: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dDuUxXoOfeEgGcCsSpaAF]")
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range)
            .map { (template as NSString).substring(with: $0.range) }
            .sorted()
    }
}
