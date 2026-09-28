import ApplicationServices
import Foundation
import IOKit
import IOKit.hid

public enum VibeKeyPermission: String, CaseIterable, Equatable, Sendable {
    case inputMonitoring
    case accessibility

    public var displayName: String {
        switch self {
        case .inputMonitoring:
            return "输入监控"
        case .accessibility:
            return "辅助功能"
        }
    }

    public var settingsTitle: String {
        "\(displayName)设置…"
    }

    public var usageDescription: String {
        switch self {
        case .inputMonitoring:
            return "读取 VibeKey 按键、旋钮和设备事件"
        case .accessibility:
            return "把 VibeKey 动作转换为系统按键"
        }
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

    public var needsAttention: Bool {
        status != .granted
    }

    public var statusTitle: String {
        switch status {
        case .granted:
            return "已授权"
        case .denied:
            return "未授权"
        case .undetermined:
            return "待授权"
        }
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
                    return AXIsProcessTrusted() ? .granted : .denied
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
