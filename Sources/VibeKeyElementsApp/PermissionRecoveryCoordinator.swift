import AppKit
import Foundation
import VibeKeyCore

/// Polls TCC permission state from a fresh child instance of the `.app` bundle
/// so stale per-process TCC caches recover automatically via a guarded relaunch.
final class PermissionRecoveryCoordinator {
    private let probeInterval: TimeInterval = 60
    private let relaunchCooldown: TimeInterval = 60
    private let relaunchTimestampKey = "lastPermissionRelaunchTimestamp"
    private let permissionCenter: VibeKeyPermissionCenter
    private let loggerProvider: () -> VibeKeyFileLogger?

    private var probeTimer: Timer?
    private var isProbeInFlight = false
    private let stateLock = NSLock()
    private let probeQueue = DispatchQueue(label: "com.patrickfu.vibekey.permission-probe", qos: .utility)

    init(
        permissionCenter: VibeKeyPermissionCenter = .live,
        loggerProvider: @escaping () -> VibeKeyFileLogger? = { VibeKeyHIDManager.shared.eventLogger }
    ) {
        self.permissionCenter = permissionCenter
        self.loggerProvider = loggerProvider
    }

    deinit {
        stop()
    }

    func stop() {
        probeTimer?.invalidate()
        probeTimer = nil
    }

    func updateProbeTimer() {
        let missing = permissionCenter.check().contains { $0.needsAttention }
        if !missing {
            stop()
            UserDefaults.standard.removeObject(forKey: relaunchTimestampKey)
            return
        }
        guard probeTimer == nil else { return }

        probeTimer = Timer.scheduledTimer(
            withTimeInterval: probeInterval,
            repeats: true
        ) { [weak self] _ in
            self?.probeForFreshPermissionsIfNeeded()
        }
    }

    func probeForFreshPermissionsIfNeeded() {
        let current = currentPermissionStatuses()
        guard current.values.contains(where: { $0 != .granted }) else {
            updateProbeTimer()
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let lastRelaunch = UserDefaults.standard.double(forKey: relaunchTimestampKey)
        let elapsed = Date().timeIntervalSince1970 - lastRelaunch
        guard elapsed >= relaunchCooldown else { return }

        let bundleURL = Bundle.main.bundleURL
        let resultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibekey-permission-probe-\(UUID().uuidString).json")
        try? FileManager.default.removeItem(at: resultURL)

        stateLock.lock()
        guard !isProbeInFlight else {
            stateLock.unlock()
            return
        }
        isProbeInFlight = true
        stateLock.unlock()

        loggerProvider()?.log("permission.probe.started", fields: [
            "current": current.sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue)=\($0.value.rawValue)" }.joined(separator: ",")
        ])

        probeQueue.async { [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: resultURL)
                self.stateLock.lock()
                self.isProbeInFlight = false
                self.stateLock.unlock()
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [
                "-g",
                "-n",
                bundleURL.path,
                "--args",
                VibeKeyPermissionProbe.argument,
                resultURL.path
            ]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                self.loggerProvider()?.log("permission.probe.failed", fields: [
                    "stage": "launch",
                    "error": error.localizedDescription
                ])
                return
            }

            guard process.terminationStatus == EXIT_SUCCESS,
                  let data = try? Data(contentsOf: resultURL),
                  let fresh = VibeKeyPermissionProbe.decoded(data) else {
                self.loggerProvider()?.log("permission.probe.failed", fields: [
                    "stage": "result",
                    "exit": String(process.terminationStatus)
                ])
                return
            }

            let newlyGranted = VibeKeyPermissionProbe.newlyGranted(current: current, fresh: fresh)
            self.loggerProvider()?.log("permission.probe.result", fields: [
                "fresh": fresh.sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue)=\($0.value.rawValue)" }.joined(separator: ","),
                "newlyGranted": newlyGranted.map(\.rawValue).sorted().joined(separator: ",")
            ])
            guard !newlyGranted.isEmpty else { return }

            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: self.relaunchTimestampKey
            )
            DispatchQueue.main.async {
                self.relaunchForFreshPermissions(permissions: newlyGranted)
            }
        }
    }

    private func currentPermissionStatuses() -> [VibeKeyPermission: VibeKeyPermissionStatus] {
        Dictionary(uniqueKeysWithValues: permissionCenter.check().map {
            ($0.permission, $0.status)
        })
    }

    private func relaunchForFreshPermissions(permissions: [VibeKeyPermission]) {
        loggerProvider()?.log("permission.relaunch.started", fields: [
            "permissions": permissions.map(\.rawValue).sorted().joined(separator: ",")
        ])

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", Bundle.main.bundleURL.path]
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            loggerProvider()?.log("permission.relaunch.failed", fields: [
                "error": error.localizedDescription
            ])
        }
    }
}
