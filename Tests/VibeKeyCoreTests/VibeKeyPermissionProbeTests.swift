import XCTest
@testable import VibeKeyCore

final class VibeKeyPermissionProbeTests: XCTestCase {
    func testProbeArgumentsRequireResultPath() {
        XCTAssertNil(VibeKeyPermissionProbe.resultPath(from: []))
        XCTAssertNil(VibeKeyPermissionProbe.resultPath(from: ["--vibekey-permission-probe"]))
        XCTAssertNil(VibeKeyPermissionProbe.resultPath(from: ["--vibekey-permission-probe", ""]))
        XCTAssertEqual(
            VibeKeyPermissionProbe.resultPath(from: ["--vibekey-permission-probe", "/tmp/status.json"]),
            "/tmp/status.json"
        )
    }

    func testStatusRoundTripKeepsEveryPermission() throws {
        let reports = [
            VibeKeyPermissionReport(permission: .inputMonitoring, status: .denied),
            VibeKeyPermissionReport(permission: .accessibility, status: .granted)
        ]
        let data = try XCTUnwrap(VibeKeyPermissionProbe.encoded(reports))
        let decoded = try XCTUnwrap(VibeKeyPermissionProbe.decoded(data))

        XCTAssertEqual(decoded[.inputMonitoring], .denied)
        XCTAssertEqual(decoded[.accessibility], .granted)
    }

    func testDecodingRejectsIncompleteOrInvalidStatuses() throws {
        XCTAssertNil(VibeKeyPermissionProbe.decoded(Data("{}".utf8)))
        XCTAssertNil(VibeKeyPermissionProbe.decoded(Data("not-json".utf8)))

        let incomplete = try XCTUnwrap(VibeKeyPermissionProbe.encoded([
            VibeKeyPermissionReport(permission: .accessibility, status: .granted)
        ]))
        XCTAssertNil(VibeKeyPermissionProbe.decoded(incomplete))
    }

    func testNewlyGrantedOnlyPromotesFormerlyMissingPermissions() {
        let current: [VibeKeyPermission: VibeKeyPermissionStatus] = [
            .inputMonitoring: .denied,
            .accessibility: .granted
        ]
        let fresh: [VibeKeyPermission: VibeKeyPermissionStatus] = [
            .inputMonitoring: .granted,
            .accessibility: .granted
        ]

        XCTAssertEqual(VibeKeyPermissionProbe.newlyGranted(current: current, fresh: fresh), [.inputMonitoring])
    }

    func testNoRelaunchWhenFreshStateStillMissingOrAlreadyGranted() {
        let current: [VibeKeyPermission: VibeKeyPermissionStatus] = [
            .inputMonitoring: .denied,
            .accessibility: .granted
        ]
        let stillMissing: [VibeKeyPermission: VibeKeyPermissionStatus] = current
        let alreadyGranted: [VibeKeyPermission: VibeKeyPermissionStatus] = [
            .inputMonitoring: .granted,
            .accessibility: .granted
        ]

        XCTAssertTrue(VibeKeyPermissionProbe.newlyGranted(current: current, fresh: stillMissing).isEmpty)
        XCTAssertTrue(VibeKeyPermissionProbe.newlyGranted(current: alreadyGranted, fresh: alreadyGranted).isEmpty)
    }
}
