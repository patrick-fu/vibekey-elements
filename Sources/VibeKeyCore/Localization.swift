import Foundation

/// UI languages shipped with VibeKey Elements. Raw values are the
/// localization identifiers declared in the app's `CFBundleLocalizations`.
public enum VibeKeyLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case french = "fr"
    case simplifiedChinese = "zh-Hans"
}

/// Resolves the active UI language and formats localized strings.
///
/// Strings live in Swift tables (see `Localization+*.swift`) instead of
/// `.strings` resources so the standalone CLI binary and the hand-assembled
/// app bundle need no SwiftPM resource bundle at runtime. Every table is an
/// exhaustive `switch`, so a missing translation is a compile error.
public enum VibeKeyLocalization {
    /// Environment variable that forces a language (e.g. `VIBEKEY_LANG=fr`).
    public static let environmentKey = "VIBEKEY_LANG"

    private static let lock = NSLock()
    private static var resolvedLanguage: VibeKeyLanguage?

    /// The active language. Resolved once from `VIBEKEY_LANG`, then the user's
    /// preferred languages (including the per-app language set in System
    /// Settings); English is the fallback. Assigning overrides it.
    public static var language: VibeKeyLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let resolvedLanguage { return resolvedLanguage }
            let language = resolve(
                preferredLanguages: Locale.preferredLanguages,
                environment: ProcessInfo.processInfo.environment
            )
            resolvedLanguage = language
            return language
        }
        set {
            lock.lock()
            resolvedLanguage = newValue
            lock.unlock()
        }
    }

    public static func resolve(
        preferredLanguages: [String],
        environment: [String: String] = [:]
    ) -> VibeKeyLanguage {
        let supported = VibeKeyLanguage.allCases.map(\.rawValue)
        if let forced = environment[environmentKey], !forced.isEmpty,
           let match = Bundle.preferredLocalizations(from: supported, forPreferences: [forced]).first,
           let language = VibeKeyLanguage(rawValue: match),
           // preferredLocalizations falls back to the first entry; only honor real matches.
           language != .english || forced.lowercased().hasPrefix("en") {
            return language
        }
        let match = Bundle.preferredLocalizations(from: supported, forPreferences: preferredLanguages).first
        return match.flatMap(VibeKeyLanguage.init(rawValue:)) ?? .english
    }

    /// Returns the template for `key` in `language` (defaults to the active one).
    public static func template(_ key: L10nKey, language: VibeKeyLanguage? = nil) -> String {
        switch language ?? self.language {
        case .english: return englishString(key)
        case .french: return frenchString(key)
        case .simplifiedChinese: return simplifiedChineseString(key)
        }
    }

    /// Localized string for `key`. Arguments fill `%@` / `%1$@` placeholders;
    /// templates that take arguments must escape a literal percent as `%%`.
    public static func string(_ key: L10nKey, _ args: CustomStringConvertible..., language: VibeKeyLanguage? = nil) -> String {
        format(template(key, language: language), args)
    }

    public static func format(_ template: String, _ args: [CustomStringConvertible]) -> String {
        guard !args.isEmpty else { return template }
        return String(format: template, arguments: args.map { $0.description as NSString })
    }
}

/// Internal shorthand used across VibeKeyCore.
func tr(_ key: L10nKey, _ args: CustomStringConvertible...) -> String {
    VibeKeyLocalization.format(VibeKeyLocalization.template(key), args)
}

/// Every user-facing string. Add a case here, then the compiler will require
/// a translation in each `Localization+*.swift` table.
public enum L10nKey: String, CaseIterable, Sendable {
    // Generic
    case deviceName
    case labelValue
    case listSeparator
    case save
    case cancel
    case quit
    case unknown
    case loading
    case charging
    case onBattery
    case batteryValue

    // Field labels
    case labelBattery
    case labelStatus
    case labelFirmware
    case labelSerial
    case labelStandby
    case labelDeepSleep
    case labelNoiseReduction
    case labelMicrophone

    // Device / connection states
    case stateConnected
    case stateNotConnected
    case stateOffline
    case stateDeviceOn
    case stateDeviceOff
    case stateDeviceLoading
    case statePowerSaving
    case stateHardwareStandby
    case stateDeviceStandby
    case stateDeviceAwake
    case stateDeviceOffReceiverConnected
    case stateDevicePoweredOn
    case micShortOn
    case micShortMuted
    case micShortOnDefault
    case micShortOff
    case micOn
    case micMuted

    // Input controls
    case controlTopButton
    case controlMiddleButton
    case controlBottomButton
    case controlKnobPress
    case controlKnobLeft
    case controlKnobRight

    // LED modes
    case ledAuto
    case ledSolid
    case ledBreathing
    case ledOff

    // Preset actions
    case presetFn
    case presetEnter
    case presetCmdDelete
    case presetScrollUp
    case presetScrollDown
    case presetSelectAll
    case presetCopy
    case presetPaste
    case presetUndo
    case presetPlayPause
    case presetMute
    case presetVolumeUp
    case presetVolumeDown
    case presetNone

    // Permissions
    case permissionInputMonitoring
    case permissionAccessibility
    case permissionSettingsTitle
    case permissionInputMonitoringUsage
    case permissionAccessibilityUsage
    case permissionGranted
    case permissionDenied
    case permissionUndetermined
    case permissionChecking
    case permissionCheckAndGrant
    case permissionOpenSettings
    case permissionTooltipGranted
    case permissionTooltipMissing
    case permissionAllGranted
    case permissionMissing

    // Shortcut recorder
    case recorderPrompt
    case recorderCancelled
    case recorderUnsupported

    // Settings panel
    case panelSubtitle
    case panelDetecting
    case panelPressToWake
    case panelBatteryCached
    case panelBatteryLoading
    case panelNotConnected
    case panelPlugIn
    case sectionPermissions
    case sectionMapping
    case sectionHardware
    case sectionMaintenance
    case sectionConnectionMode
    case buttonCheckAllPermissions
    case buttonResetKeys
    case buttonFactoryReset
    case buttonReboot
    case buttonRefresh
    case buttonCheckUpdates
    case longConnectMode

    // Mapping
    case mappingCustomItem
    case mappingCustomButton
    case mappingCustomCurrent
    case customTitle
    case customMessage
    case customPlaceholder
    case customInvalidTitle
    case customInvalidMessage

    // Hardware options
    case hwNoiseReduction
    case hwMicrophone
    case hwLED
    case hwStandby
    case hwSleep
    case noiseLevel0
    case noiseLevel1
    case noiseLevel2
    case noiseLevel3
    case noiseShort0
    case noiseShort1
    case noiseShort2
    case noiseShort3
    case standby5Min
    case standby15Min
    case standby30Min
    case standbyNever
    case sleep30Min
    case sleep1Hour
    case sleep2Hours
    case sleep4Hours

    // Status bar context menu
    case menuFirmwareVersion
    case menuSerialNumber
    case menuOpenPanel
    case menuCheckPermissions
    case menuKeyMapping
    case menuNoiseReduction
    case menuMicrophone
    case menuLEDMode
    case menuQuitApp
}
