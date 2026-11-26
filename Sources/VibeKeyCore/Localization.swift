import Foundation

/// UI languages shipped with VibeKey Elements. Raw values are the
/// localization identifiers declared in the app's `CFBundleLocalizations`.
public enum VibeKeyLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case french = "fr"
    case simplifiedChinese = "zh-Hans"
}

/// Resolves the active UI language from environment overrides and macOS
/// preferences.
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

    /// Returns the localized static string for `key` in `language` (defaults to the active one).
    public static func string(_ key: L10nKey, language: VibeKeyLanguage? = nil) -> String {
        VibeKeyStrings(language: language ?? self.language)[key]
    }
}

/// Immutable, thread-safe string catalog bound to a single `VibeKeyLanguage`.
///
/// Static strings are looked up via `strings[.someKey]`; parameterized messages
/// are exposed as typed methods so callers and translations are checked at
/// compile time without C-style `String(format:)` varargs.
public struct VibeKeyStrings: Equatable, Sendable {
    public let language: VibeKeyLanguage

    public init(language: VibeKeyLanguage) {
        self.language = language
    }

    public static var current: VibeKeyStrings {
        VibeKeyStrings(language: VibeKeyLocalization.language)
    }

    public subscript(_ key: L10nKey) -> String {
        switch language {
        case .english: return VibeKeyLocalization.englishString(key)
        case .french: return VibeKeyLocalization.frenchString(key)
        case .simplifiedChinese: return VibeKeyLocalization.simplifiedChineseString(key)
        }
    }

    // MARK: - Type-safe parameterized strings

    public func labelValue(_ label: String, _ value: String) -> String {
        switch language {
        case .english, .simplifiedChinese:
            return "\(label): \(value)"
        case .french:
            return "\(label)\u{202F}: \(value)"
        }
    }

    public func labelValue(_ label: L10nKey, _ value: String) -> String {
        labelValue(self[label], value)
    }

    public func batteryValue(percent: UInt16, state: String, voltageMillivolts: UInt16) -> String {
        switch language {
        case .english, .simplifiedChinese:
            return "\(percent)% (\(state), \(voltageMillivolts)mV)"
        case .french:
            return "\(percent)\u{202F}% (\(state), \(voltageMillivolts)\u{202F}mV)"
        }
    }

    public func batteryValue(_ status: VibeKeyBatteryStatus) -> String {
        batteryValue(
            percent: status.percent,
            state: self[status.isCharging ? .charging : .onBattery],
            voltageMillivolts: status.voltageMillivolts
        )
    }

    public func permissionSettingsTitle(_ permissionName: String) -> String {
        switch language {
        case .english:
            return "\(permissionName) Settings…"
        case .french:
            return "Réglages «\u{00A0}\(permissionName)\u{00A0}»…"
        case .simplifiedChinese:
            return "\(permissionName)设置…"
        }
    }

    public func permissionTooltipGranted(_ permissionName: String) -> String {
        switch language {
        case .english:
            return "Open \(permissionName) settings"
        case .french:
            return "Ouvrir les réglages «\u{00A0}\(permissionName)\u{00A0}»"
        case .simplifiedChinese:
            return "打开\(permissionName)设置面板"
        }
    }

    public func permissionTooltipMissing(usage: String, permissionName: String) -> String {
        switch language {
        case .english:
            return "\(usage). Click to open \(permissionName) settings."
        case .french:
            return "\(usage). Cliquez pour ouvrir les réglages «\u{00A0}\(permissionName)\u{00A0}»."
        case .simplifiedChinese:
            return "\(usage)；点击后打开\(permissionName)设置面板"
        }
    }

    public func permissionMissing(_ permissionNames: [String]) -> String {
        let joined = permissionNames.joined(separator: self[.listSeparator])
        switch language {
        case .english:
            return "○ Permissions needed: \(joined)"
        case .french:
            return "○ Autorisations requises\u{202F}: \(joined)"
        case .simplifiedChinese:
            return "○ 系统权限：\(joined)待授权"
        }
    }

    public func mappingCustomCurrent(_ encodedAction: String) -> String {
        switch language {
        case .english:
            return "Custom: \(encodedAction)"
        case .french:
            return "Personnalisé\u{202F}: \(encodedAction)"
        case .simplifiedChinese:
            return "自定义: \(encodedAction)"
        }
    }

    public func customTitle(_ controlName: String) -> String {
        switch language {
        case .english:
            return "Customize \(controlName)"
        case .french:
            return "Personnaliser «\u{00A0}\(controlName)\u{00A0}»"
        case .simplifiedChinese:
            return "自定义 \(controlName)"
        }
    }

    public func menuFirmwareVersion(_ version: String) -> String {
        switch language {
        case .english:
            return "Firmware version: \(version)"
        case .french:
            return "Version du firmware\u{202F}: \(version)"
        case .simplifiedChinese:
            return "固件版本: \(version)"
        }
    }

    public func menuSerialNumber(_ serial: String) -> String {
        switch language {
        case .english:
            return "Serial number: \(serial)"
        case .french:
            return "Numéro de série\u{202F}: \(serial)"
        case .simplifiedChinese:
            return "序列号: \(serial)"
        }
    }
}

/// Every static user-facing string. Add a case here, then the compiler will
/// require a translation in each `Localization+*.swift` table.
/// Parameterized strings live as typed methods on `VibeKeyStrings`.
public enum L10nKey: String, CaseIterable, Sendable {
    // Generic
    case deviceName
    case listSeparator
    case save
    case cancel
    case quit
    case unknown
    case loading
    case charging
    case onBattery

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

    // Controls
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
    case permissionInputMonitoringUsage
    case permissionAccessibilityUsage
    case permissionGranted
    case permissionDenied
    case permissionUndetermined
    case permissionChecking
    case permissionCheckAndGrant
    case permissionOpenSettings
    case permissionAllGranted

    // Shortcut recorder
    case recorderPrompt
    case recorderCancelled
    case recorderUnsupported

    // Settings panel chrome
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

    // Custom action dialog
    case mappingCustomItem
    case mappingCustomButton
    case customMessage
    case customPlaceholder
    case customInvalidTitle
    case customInvalidMessage

    // Hardware controls
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

    // Context menu
    case menuOpenPanel
    case menuCheckPermissions
    case menuKeyMapping
    case menuNoiseReduction
    case menuMicrophone
    case menuLEDMode
    case menuQuitApp
}
