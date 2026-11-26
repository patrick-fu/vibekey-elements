import ApplicationServices
import Foundation
import IOKit
import IOKit.hid

public enum VibeKeyPermission: String, CaseIterable, Equatable, Sendable {
    case inputMonitoring
    case accessibility

    public func displayName(in language: VibeKeyLanguage) -> String {
        let strings = VibeKeyStrings(language: language)
        switch self {
        case .inputMonitoring:
            return strings[.permissionInputMonitoring]
        case .accessibility:
            return strings[.permissionAccessibility]
        }
    }

    public var displayName: String {
        displayName(in: VibeKeyLocalization.language)
    }

    public func settingsTitle(in language: VibeKeyLanguage) -> String {
        VibeKeyStrings(language: language).permissionSettingsTitle(displayName(in: language))
    }

    public var settingsTitle: String {
        settingsTitle(in: VibeKeyLocalization.language)
    }

    public func usageDescription(in language: VibeKeyLanguage) -> String {
        let strings = VibeKeyStrings(language: language)
        switch self {
        case .inputMonitoring:
            return strings[.permissionInputMonitoringUsage]
        case .accessibility:
            return strings[.permissionAccessibilityUsage]
        }
    }

    public var usageDescription: String {
        usageDescription(in: VibeKeyLocalization.language)
    }

    public var settingsURL: URL? {
        let fragment: String
        switch self {
        case .inputMonitoring:
            fragment = "Privacy_ListenEvent"
        case .accessibility:
            fragment = "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(fragment)")
    }
}

public enum VibeKeyPermissionStatus: String, Equatable, Sendable {
    case granted
    case denied
    case undetermined
}

public struct VibeKeyPermissionReport: Equatable, Sendable {
    public let permission: VibeKeyPermission
    public let status: VibeKeyPermissionStatus

    public init(permission: VibeKeyPermission, status: VibeKeyPermissionStatus) {
        self.permission = permission
        self.status = status
    }

    public var needsAttention: Bool {
        status != .granted
    }

    public func statusTitle(in language: VibeKeyLanguage) -> String {
        let strings = VibeKeyStrings(language: language)
        switch status {
        case .granted:
            return strings[.permissionGranted]
        case .denied:
            return strings[.permissionDenied]
        case .undetermined:
            return strings[.permissionUndetermined]
        }
    }

    public var statusTitle: String {
        statusTitle(in: VibeKeyLocalization.language)
    }
}

public struct VibeKeyPermissionCenter: Sendable {
    public let statusProvider: @Sendable (VibeKeyPermission) -> VibeKeyPermissionStatus
    public let requestHandler: @Sendable (VibeKeyPermission) -> Void
    public let settingsOpener: @Sendable (URL) -> Void

    public init(
        statusProvider: @escaping @Sendable (VibeKeyPermission) -> VibeKeyPermissionStatus,
        requestHandler: @escaping @Sendable (VibeKeyPermission) -> Void,
        settingsOpener: @escaping @Sendable (URL) -> Void
    ) {
        self.statusProvider = statusProvider
        self.requestHandler = requestHandler
        self.settingsOpener = settingsOpener
    }

    public static var live: VibeKeyPermissionCenter {
        VibeKeyPermissionCenter(
            statusProvider: { permission in
                switch permission {
                case .inputMonitoring:
                    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
                    if access == kIOHIDAccessTypeGranted {
                        return .granted
                    }
                    if access == kIOHIDAccessTypeUnknown {
                        return .undetermined
                    }
                    return .denied
                case .accessibility:
                    let options = [
                        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
                    ] as CFDictionary
                    return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
                }
            },
            requestHandler: { permission in
                switch permission {
                case .inputMonitoring:
                    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
                case .accessibility:
                    let options = [
                        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                    ] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            },
            settingsOpener: { _ in }
        )
    }

    public func check() -> [VibeKeyPermissionReport] {
        VibeKeyPermission.allCases.map { permission in
            VibeKeyPermissionReport(
                permission: permission,
                status: statusProvider(permission)
            )
        }
    }

    @discardableResult
    public func requestMissingAndOpenSettings() -> [VibeKeyPermissionReport] {
        let reports = check()
        let missing = reports.filter(\.needsAttention)

        for report in missing {
            requestHandler(report.permission)
        }
        if let firstMissing = missing.first, let url = firstMissing.permission.settingsURL {
            settingsOpener(url)
        }
        return reports
    }
}

extension VibeKeyPermissionCenter {
    @discardableResult
    public func requestAndOpenSettings(_ permission: VibeKeyPermission) -> VibeKeyPermissionReport {
        let report = VibeKeyPermissionReport(permission: permission, status: statusProvider(permission))
        guard report.needsAttention else { return report }

        requestHandler(permission)
        if let url = permission.settingsURL {
            settingsOpener(url)
        }
        return report
    }

    public func openSettings(for permission: VibeKeyPermission) {
        if let url = permission.settingsURL {
            settingsOpener(url)
        }
    }
}
