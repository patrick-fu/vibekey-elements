import XCTest
@testable import VibeKeyCore

private final class PermissionRecorder<Value>: @unchecked Sendable {
    private(set) var values: [Value] = []

    func add(_ value: Value) {
        values.append(value)
    }
}

final class VibeKeyPermissionTests: XCTestCase {
    func testRequiredPermissionsAreOnlyHIDAndKeyInjectionPermissions() {
        XCTAssertEqual(
            VibeKeyPermission.allCases,
            [.inputMonitoring, .accessibility]
        )
    }

    func testEveryRequiredPermissionHasChineseGuidanceAndSettingsURL() {
        for permission in VibeKeyPermission.allCases {
            XCTAssertFalse(permission.usageDescription.isEmpty)
            XCTAssertFalse(permission.settingsTitle.isEmpty)
            XCTAssertNotNil(permission.settingsURL)
        }
        XCTAssertEqual(
            VibeKeyPermission.inputMonitoring.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        XCTAssertEqual(
            VibeKeyPermission.accessibility.settingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testCheckCollectsStatusesInStableOrder() {
        let center = VibeKeyPermissionCenter(
            statusProvider: { permission in
                permission == .inputMonitoring ? .denied : .granted
            },
            requestHandler: { _ in },
            settingsOpener: { _ in }
        )

        let reports = center.check()

        XCTAssertEqual(reports.map(\.permission), [.inputMonitoring, .accessibility])
        XCTAssertEqual(reports.map(\.status), [.denied, .granted])
        XCTAssertTrue(reports[0].needsAttention)
        XCTAssertFalse(reports[1].needsAttention)
    }

    func testRequestAndOpenFirstMissingOnlyRequestsBlockedPermission() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { permission in
                permission == .inputMonitoring ? .denied : .granted
            },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        let reports = center.requestMissingAndOpenSettings()

        XCTAssertEqual(requested.values, [.inputMonitoring])
        XCTAssertEqual(opened.values.count, 1)
        XCTAssertEqual(reports.first(where: { $0.permission == .inputMonitoring })?.status, .denied)
    }

    func testRequestAndOpenFirstMissingUsesInputMonitoringBeforeAccessibility() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { _ in .denied },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        _ = center.requestMissingAndOpenSettings()

        XCTAssertEqual(requested.values, [.inputMonitoring, .accessibility])
        XCTAssertEqual(opened.values.count, 1)
        XCTAssertEqual(opened.values, [VibeKeyPermission.inputMonitoring.settingsURL].compactMap { $0 })
    }

    func testAllGrantedDoesNotPromptOrOpenSettings() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { _ in .granted },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        let reports = center.requestMissingAndOpenSettings()

        XCTAssertTrue(requested.values.isEmpty)
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertTrue(reports.allSatisfy { !$0.needsAttention })
    }
}

final class VibeKeySinglePermissionTests: XCTestCase {
    func testSingleMissingPermissionPromptsAndOpensOnlyItsSettings() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { $0 == .accessibility ? .denied : .granted },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        let report = center.requestAndOpenSettings(.accessibility)

        XCTAssertEqual(requested.values, [.accessibility])
        XCTAssertEqual(opened.values, [VibeKeyPermission.accessibility.settingsURL].compactMap { $0 })
        XCTAssertTrue(report.needsAttention)
    }

    func testSingleGrantedPermissionDoesNotPrompt() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { _ in .granted },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        _ = center.requestAndOpenSettings(.inputMonitoring)

        XCTAssertTrue(requested.values.isEmpty)
        XCTAssertTrue(opened.values.isEmpty)
    }
}

final class VibeKeyDeniedInputMonitoringTests: XCTestCase {
    func testDeniedInputMonitoringPromptsAndOpensListenEventPane() {
        let requested = PermissionRecorder<VibeKeyPermission>()
        let opened = PermissionRecorder<URL>()
        let center = VibeKeyPermissionCenter(
            statusProvider: { $0 == .inputMonitoring ? .denied : .granted },
            requestHandler: { requested.add($0) },
            settingsOpener: { opened.add($0) }
        )

        let report = center.requestAndOpenSettings(.inputMonitoring)

        XCTAssertEqual(requested.values, [.inputMonitoring])
        XCTAssertEqual(opened.values, [VibeKeyPermission.inputMonitoring.settingsURL].compactMap { $0 })
        XCTAssertEqual(report.status, .denied)
        XCTAssertTrue(report.needsAttention)
    }
}
