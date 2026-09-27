import Foundation
import IOKit
import IOKit.hid
import OSLog

public enum VibeKeyHIDError: Error, Equatable, LocalizedError {
    case deviceNotConnected
    case setReportFailed(IOReturn)

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "VibeKey device is not connected."
        case let .setReportFailed(code):
            return "IOHIDDeviceSetReport failed with IOReturn code: \(code)."
        }
    }
}

private let powerLogger = Logger(subsystem: "com.patrickfu.vibekey", category: "Power")

public final class VibeKeyHIDManager: @unchecked Sendable {
    public static let shared = VibeKeyHIDManager()

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var wakeDevice: IOHIDDevice?
    private var heartbeatTimer: Timer?
    private var pollTimer: Timer?
    public private(set) var isStarted = false

    // Power saving & inactivity state
    public private(set) var isPowerSaving = false
    public private(set) var lastActivityTime = Date()
    public var standbyTimeoutSeconds: TimeInterval = 300 // 5 minutes factory default

    // State guards & counters
    private var heartbeatInFlight = false
    private var onlineGeneration: UInt64 = 0

    // Persistent heap buffers for IOHID input report callbacks
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportCapacity = 64

    private var wakeReportBuffer: UnsafeMutablePointer<UInt8>?
    private var wakeReportCapacity = 64

    // Serial number chunks collector
    private var snChunks: [Int: String] = [:]

    // Current snapshot
    public private(set) var currentSnapshot = VibeKeyDeviceInfoSnapshot()

    public var onDeviceConnected: (() -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onBatteryUpdated: ((VibeKeyBatteryStatus) -> Void)?
    public var onDeviceInfoUpdated: ((VibeKeyDeviceInfoSnapshot) -> Void)?
    public var onEventReceived: ((InputControl, ButtonPhase) -> Void)?
    public var onPowerSavingChanged: ((Bool) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.patrickfu.vibekey.hid.io", qos: .userInitiated)

    public init() {}

    deinit {
        stop()
    }

    public static func hasInputMonitoringAccess() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    public static func requestInputMonitoringAccess() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public func start() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.start() }
            return
        }
        guard !isStarted else { return }
        isStarted = true
        setupHIDManager()
    }

    public func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.stop() }
            return
        }
        guard isStarted else { return }
        isStarted = false
        stopTimers()

        if let device = connectedDevice {
            // Send clean offline notification before detaching
            if let offlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(false) {
                _ = try? sendReportSync(offlineReport, to: device)
            }
            detachInputDevice(device)
            connectedDevice = nil
        }

        if let device = wakeDevice {
            detachWakeDevice(device)
            wakeDevice = nil
        }

        if let manager = hidManager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        hidManager = nil
        isPowerSaving = false
        currentSnapshot = VibeKeyDeviceInfoSnapshot()
    }

    public func enterPowerSaving(isStandby: Bool = true, reason: String = "Inactivity") {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.enterPowerSaving(isStandby: isStandby, reason: reason) }
            return
        }
        guard !isPowerSaving else { return }
        isPowerSaving = true
        currentSnapshot.isStandby = isStandby
        powerLogger.info("Entering power saving mode (isStandby: \(isStandby, privacy: .public), reason: \(reason, privacy: .public)). Halting heartbeat & polling timers.")
        stopTimers()

        if let device = connectedDevice {
            ioQueue.async { [weak self] in
                guard let self = self else { return }
                // Let MCU return to low-power native standby by releasing online mode
                if let offlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(false) {
                    _ = try? self.sendReportSync(offlineReport, to: device)
                    powerLogger.debug("Transmitted softwareOnline(false) to MCU. Downlink RF transmission paused.")
                }
            }
        }

        onPowerSavingChanged?(true)
        onDeviceInfoUpdated?(currentSnapshot)
    }

    public func resumeFromPowerSaving(reason: String = "UserActivity") {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.resumeFromPowerSaving(reason: reason) }
            return
        }
        guard isPowerSaving else { return }
        isPowerSaving = false
        currentSnapshot.isStandby = false
        lastActivityTime = Date()
        powerLogger.info("Resuming from power saving mode (reason: \(reason, privacy: .public)). Restoring software online, heartbeat & polling timers.")

        if let device = connectedDevice {
            onlineGeneration &+= 1
            let generation = self.onlineGeneration
            ioQueue.async { [weak self] in
                guard let self = self, self.onlineGeneration == generation else { return }
                if let onlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(true) {
                    _ = try? self.sendReportSync(onlineReport, to: device)
                    powerLogger.debug("Transmitted softwareOnline(true) to MCU.")
                }
                if let heartbeatReport = try? VibeKeyPacketBuilder.heartbeatReport() {
                    _ = try? self.sendReportSync(heartbeatReport, to: device)
                }
                DispatchQueue.main.async {
                    guard self.onlineGeneration == generation, !self.isPowerSaving else { return }
                    self.startHeartbeat()
                    self.startPeriodicPolling()
                    self.refreshDeviceInfo()
                }
            }
        }

        onPowerSavingChanged?(false)
        onDeviceInfoUpdated?(currentSnapshot)
    }

    public func hostWillSleep() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.hostWillSleep() }
            return
        }
        powerLogger.notice("macOS host sleep/power-off notification received. Forcing standby power saving mode.")
        enterPowerSaving(isStandby: true, reason: "HostSleep")
    }

    public func hostDidWake() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.hostDidWake() }
            return
        }
        powerLogger.notice("macOS host did wake notification received. Current isPowerSaving=\(self.isPowerSaving, privacy: .public). Maintaining zero-downlink standby to prevent DarkWake RF wakeups.")
        // If device is in power saving, remain in standby to prevent macOS DarkWake
        // and background maintenance from emitting RF packets and waking VibeKey overnight.
        // Device will immediately resume when the user presses any key.
        if !isPowerSaving {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, self.connectedDevice != nil, !self.isPowerSaving else { return }
                self.refreshDeviceInfo()
            }
        }
    }

    private func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let customMatching: [String: Any] = [
            kIOHIDVendorIDKey as String: VibeKeyDeviceInfo.vendorID,
            kIOHIDProductIDKey as String: VibeKeyDeviceInfo.productID,
            kIOHIDPrimaryUsagePageKey as String: VibeKeyDeviceInfo.usagePage,
            kIOHIDPrimaryUsageKey as String: VibeKeyDeviceInfo.usage
        ]

        let wakeMatching: [String: Any] = [
            kIOHIDVendorIDKey as String: VibeKeyDeviceInfo.vendorID,
            kIOHIDProductIDKey as String: VibeKeyDeviceInfo.productID,
            kIOHIDPrimaryUsagePageKey as String: 0x000C,
            kIOHIDPrimaryUsageKey as String: 1
        ]

        IOHIDManagerSetDeviceMatchingMultiple(
            manager,
            [customMatching as CFDictionary, wakeMatching as CFDictionary] as CFArray
        )

        let matchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard result == kIOReturnSuccess, let context = context else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            instance.handleDeviceMatched(device)
        }

        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard result == kIOReturnSuccess, let context = context else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            instance.handleDeviceRemoved(device)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, selfPtr)

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            powerLogger.error("IOHIDManagerOpen failed (\(openStatus, privacy: .public)). Leaving HID manager stopped for retry.")
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
            isStarted = false
            return
        }

        // Check if devices are already plugged in
        if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in existingDevices {
                handleDeviceMatched(device)
            }
        }
    }

    private func primaryUsagePage(for device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return -1
        }
        var usagePage: Int32 = -1
        CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &usagePage)
        return Int(usagePage)
    }

    private func maxInputReportSize(for device: IOHIDDevice) -> Int {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return 64
        }
        var reportedSize: Int32 = 0
        CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .sInt32Type, &reportedSize)
        return max(Int(reportedSize), 64)
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        let usagePage = primaryUsagePage(for: device)
        if usagePage == 0x000C {
            attachWakeDevice(device)
            return
        }

        guard connectedDevice == nil else { return }
        connectedDevice = device

        attachInputDevice(device)
        currentSnapshot.isConnected = true
        snChunks.removeAll()
        onlineGeneration &+= 1
        isPowerSaving = false
        lastActivityTime = Date()

        powerLogger.info("VibeKey device attached (VID: \(VibeKeyDeviceInfo.vendorID, privacy: .public), PID: \(VibeKeyDeviceInfo.productID, privacy: .public)).")
        self.onDeviceConnected?()
        self.onDeviceInfoUpdated?(self.currentSnapshot)

        // Handshake: Reset to native baseline first, then activate online mode once, and initial heartbeat
        let generation = self.onlineGeneration
        ioQueue.async { [weak self] in
            guard let self = self, self.onlineGeneration == generation else { return }

            // 1. Send offline reset packet to reset MCU firmware state cleanly
            if let offlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(false) {
                _ = try? self.sendReportSync(offlineReport, to: device)
            }
            Thread.sleep(forTimeInterval: 0.08) // 80ms baseline rest

            // 2. Enable host-online mode once (Firmware transitions to online; NOT in periodic heartbeat)
            if let onlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(true) {
                _ = try? self.sendReportSync(onlineReport, to: device)
            }

            // 3. Send initial heartbeat
            if let heartbeatReport = try? VibeKeyPacketBuilder.heartbeatReport() {
                _ = try? self.sendReportSync(heartbeatReport, to: device)
            }

            DispatchQueue.main.async {
                guard self.onlineGeneration == generation, !self.isPowerSaving else { return }
                self.startHeartbeat()
                self.startPeriodicPolling()
                self.refreshDeviceInfo()
            }
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        if let currentWake = wakeDevice, currentWake === device {
            detachWakeDevice(device)
            return
        }

        guard let current = connectedDevice, current === device else { return }
        stopTimers()
        detachInputDevice(device)
        connectedDevice = nil
        onlineGeneration &+= 1
        isPowerSaving = false
        currentSnapshot = VibeKeyDeviceInfoSnapshot(isConnected: false)
        onDeviceDisconnected?()
        onDeviceInfoUpdated?(currentSnapshot)
    }

    private func attachInputDevice(_ device: IOHIDDevice) {
        let capacity = 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)

        let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, length in
            guard result == kIOReturnSuccess, let context = context, length > 0 else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            instance.handleInputReport(reportID: reportID, bytes: bytes)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            reportCallback,
            selfPtr
        )

        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        self.inputReportBuffer = buffer
        self.inputReportCapacity = capacity
    }

    private func detachInputDevice(_ device: IOHIDDevice) {
        IOHIDDeviceUnscheduleFromRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        if let buffer = inputReportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, inputReportCapacity, nil, nil)
            buffer.deinitialize(count: inputReportCapacity)
            buffer.deallocate()
            inputReportBuffer = nil
        }
    }

    private func attachWakeDevice(_ device: IOHIDDevice) {
        guard wakeDevice == nil else { return }
        let capacity = maxInputReportSize(for: device)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)

        let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, length in
            guard result == kIOReturnSuccess, let context = context, length > 0 else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            instance.handleWakeReport(reportID: reportID, bytes: bytes)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            reportCallback,
            selfPtr
        )

        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        self.wakeDevice = device
        self.wakeReportBuffer = buffer
        self.wakeReportCapacity = capacity
    }

    private func detachWakeDevice(_ device: IOHIDDevice) {
        guard let current = wakeDevice, current === device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        if let buffer = wakeReportBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, wakeReportCapacity, nil, nil)
            buffer.deinitialize(count: wakeReportCapacity)
            buffer.deallocate()
            wakeReportBuffer = nil
        }
        wakeDevice = nil
    }

    private func handleWakeReport(reportID: UInt32, bytes: [UInt8]) {
        DispatchQueue.main.async {
            self.lastActivityTime = Date()
            if self.isPowerSaving {
                powerLogger.info("Wake report received on wake device callback. Resuming from standby.")
                self.resumeFromPowerSaving(reason: "WakeReport")
            }
        }
    }

    func applyDeviceNotice(_ notice: VibeKeyNotice) {
        switch notice {
        case let .standby(isStandby):
            if isStandby {
                powerLogger.info("Device standby notice packet received from VibeKey.")
                enterPowerSaving(isStandby: true, reason: "DeviceStandbyNotice")
            } else {
                lastActivityTime = Date()
                powerLogger.info("Device active/wake notice packet received from VibeKey.")
                resumeFromPowerSaving(reason: "DeviceStandbyNoticeExit")
            }
        case let .active(isActive):
            // AU05 emits rapid paired active/inactive notices around power-state
            // transitions. Treat them as wake confirmations only after local
            // standby handoff; otherwise they make the menu-bar state flicker.
            guard isActive, isPowerSaving else {
                powerLogger.debug("Ignoring non-wake device activity notice.")
                return
            }
            lastActivityTime = Date()
            powerLogger.info("Device active notice received.")
            resumeFromPowerSaving(reason: "DeviceActiveNotice")
        case .powerOn:
            lastActivityTime = Date()
            powerLogger.info("Device powerOn notice received.")
            resumeFromPowerSaving(reason: "DevicePowerOnNotice")
            refreshDeviceInfo()
        }
    }

    private func handleInputReport(reportID: UInt32, bytes: [UInt8]) {
        let hasExplicitID = (reportID == UInt32(VibeKeyDeviceInfo.reportID))
        guard let plaintext = try? TEACodec.decryptInputReport(bytes, hasReportID: hasExplicitID) else { return }

        // 1. Check for physical events (K1, K2, K3, Knob)
        if let event = VibeKeyParser.parseDeviceEvent(plaintext: plaintext) {
            if case let .key(control, phase) = event {
                DispatchQueue.main.async {
                    self.lastActivityTime = Date()
                    if self.isPowerSaving {
                        powerLogger.info("Physical input detected (\(control.rawValue, privacy: .public)) while in standby. Resuming.")
                        self.resumeFromPowerSaving(reason: "KeyEvent(\(control.rawValue))")
                    }
                    self.onEventReceived?(control, phase)
                }
            }
            return
        }

        // 2. Check for firmware version response (0x01, 0x04, 0x04)
        if let version = VibeKeyParser.parseFirmwareVersion(plaintext: plaintext) {
            DispatchQueue.main.async {
                self.currentSnapshot.firmwareVersion = version
                self.onDeviceInfoUpdated?(self.currentSnapshot)
            }
            return
        }

        // 3. Check for serial number chunks (0x01, 0x01, 0x0B)
        if let chunk = VibeKeyParser.parseSerialNumberChunk(plaintext: plaintext) {
            snChunks[chunk.seg] = chunk.text
            let fullSN = snChunks.keys.sorted().compactMap { self.snChunks[$0] }.joined()
            if !fullSN.isEmpty {
                DispatchQueue.main.async {
                    self.currentSnapshot.serialNumber = fullSN
                    self.onDeviceInfoUpdated?(self.currentSnapshot)
                }
            }
            return
        }

        // 4. Check for device notices (0x0B)
        if let notice = VibeKeyParser.parseDeviceNotice(plaintext: plaintext) {
            DispatchQueue.main.async {
                self.applyDeviceNotice(notice)
            }
            return
        }

        // 5. Check for power / battery responses
        if let powerResp = VibeKeyParser.parsePowerResponse(plaintext: plaintext) {
            DispatchQueue.main.async {
                switch powerResp {
                case let .battery(status):
                    self.currentSnapshot.battery = status
                    self.onBatteryUpdated?(status)
                case let .standbyTime(sec):
                    self.currentSnapshot.standbyTimeSeconds = sec
                    self.standbyTimeoutSeconds = TimeInterval(sec)
                case let .sleepTime(sec):
                    self.currentSnapshot.sleepTimeSeconds = sec
                case let .micNR(level):
                    self.currentSnapshot.micNoiseReduction = level
                case let .micEnabled(enabled):
                    self.currentSnapshot.micEnabled = enabled
                }
                self.onDeviceInfoUpdated?(self.currentSnapshot)
            }
            return
        }
    }

    public func sendCommand(_ reportBytes: [UInt8]) throws {
        guard let device = connectedDevice else {
            throw VibeKeyHIDError.deviceNotConnected
        }
        if isPowerSaving {
            resumeFromPowerSaving()
        }
        try ioQueue.sync {
            try self.sendReportSync(reportBytes, to: device)
        }
    }

    private func sendReportSync(_ reportBytes: [UInt8], to device: IOHIDDevice) throws {
        var buffer = reportBytes
        let status = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(VibeKeyDeviceInfo.reportID),
            &buffer,
            buffer.count
        )
        guard status == kIOReturnSuccess else {
            throw VibeKeyHIDError.setReportFailed(status)
        }
    }

    public func refreshDeviceInfo() {
        guard !isPowerSaving, connectedDevice != nil else { return }
        ioQueue.async { [weak self] in
            guard let self = self, !self.isPowerSaving, let device = self.connectedDevice else { return }
            // 1. Query Battery
            if let rep = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000) // 25ms gap between queries

            // 2. Query Firmware Version
            if let rep = try? VibeKeyPacketBuilder.firmwareVersionQueryReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 3. Query Serial Number
            if let rep = try? VibeKeyPacketBuilder.serialNumberQueryReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 4. Query Standby & Sleep times
            if let rep = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x2C) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)
            if let rep = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x42) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 5. Query Mic NR & Mic Enable
            if let rep = try? VibeKeyPacketBuilder.noiseReductionQueryReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)
            if let rep = try? VibeKeyPacketBuilder.microphoneEnableQueryReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
        }
    }

    public func setNoiseReduction(level: UInt8) {
        guard let rep = try? VibeKeyPacketBuilder.setNoiseReductionReport(level: level) else { return }
        try? sendCommand(rep)
    }

    public func setMicrophoneEnabled(_ enabled: Bool) {
        guard let rep = try? VibeKeyPacketBuilder.setMicrophoneEnableReport(enabled: enabled) else { return }
        try? sendCommand(rep)
    }

    public func setLEDMode(_ mode: LEDMode) {
        if mode == .auto {
            guard let rep = try? VibeKeyPacketBuilder.resetLEDReport() else { return }
            try? sendCommand(rep)
        } else {
            guard let rep = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: mode, brightness: 100) else { return }
            try? sendCommand(rep)
        }
    }

    public func setStandbyTimeout(seconds: UInt32) {
        self.standbyTimeoutSeconds = TimeInterval(seconds)
        guard let rep = try? VibeKeyPacketBuilder.setStandbyTimeoutReport(seconds: seconds) else { return }
        try? sendCommand(rep)
    }

    public func setSleepTimeout(seconds: UInt32) {
        guard let rep = try? VibeKeyPacketBuilder.setSleepTimeoutReport(seconds: seconds) else { return }
        try? sendCommand(rep)
    }

    public func rebootDevice() {
        guard let device = connectedDevice else { return }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if let rep = try? VibeKeyPacketBuilder.rebootReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
        }
    }

    public func resetHardwareDefaults() {
        guard let device = connectedDevice else { return }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            // 1. Reset Hooks & Audio system mode
            if let rep = try? VibeKeyPacketBuilder.setHooksModeReport(enabled: false) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)
            if let rep = try? VibeKeyPacketBuilder.setAudioButtonSystemModeReport(enabled: false) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 2. Reset LED to hardware auto (mode 2)
            if let rep = try? VibeKeyPacketBuilder.resetLEDReport() {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 3. Reset Mic NR to 0 (off)
            if let rep = try? VibeKeyPacketBuilder.setNoiseReductionReport(level: 0) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 4. Reset Mic Enable to true
            if let rep = try? VibeKeyPacketBuilder.setMicrophoneEnableReport(enabled: true) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 5. Reset Standby to factory 300s
            if let rep = try? VibeKeyPacketBuilder.setStandbyTimeoutReport(seconds: 300) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 6. Reset Sleep to factory 3600s
            if let rep = try? VibeKeyPacketBuilder.setSleepTimeoutReport(seconds: 3600) {
                _ = try? self.sendReportSync(rep, to: device)
            }
            usleep(25_000)

            // 7. Software online reaffirmation & initial heartbeat
            if let onlineRep = try? VibeKeyPacketBuilder.softwareOnlineReport(true) {
                _ = try? self.sendReportSync(onlineRep, to: device)
            }
            usleep(25_000)
            if let hbRep = try? VibeKeyPacketBuilder.heartbeatReport() {
                _ = try? self.sendReportSync(hbRep, to: device)
            }

            DispatchQueue.main.async {
                self.refreshDeviceInfo()
            }
        }
    }

    public func queryBattery() {
        guard !isPowerSaving,
              connectedDevice != nil,
              let report = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02) else { return }
        ioQueue.async { [weak self] in
            guard let self = self, !self.isPowerSaving, let device = self.connectedDevice else { return }
            _ = try? self.sendReportSync(report, to: device)
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatInFlight = false
        let generation = self.onlineGeneration

        // 0.8 second interval matching vendor and community proven timing.
        // NOTE: Only sends heartbeatReport() (06 01 23 00 01), NEVER sends softwareOnlineReport(true)!
        // Sending softwareOnlineReport in heartbeat causes LED flashing and firmware watchdog reset cycles.
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self,
                  let device = self.connectedDevice,
                  self.onlineGeneration == generation,
                  !self.heartbeatInFlight else { return }

            // Inactivity Check: if device has been idle past standbyTimeoutSeconds (0 means disabled), enter power saving
            let elapsed = Date().timeIntervalSince(self.lastActivityTime)
            if self.standbyTimeoutSeconds > 0 && elapsed >= self.standbyTimeoutSeconds {
                powerLogger.info("Device idle threshold reached (\(Int(elapsed), privacy: .public)s >= \(Int(self.standbyTimeoutSeconds), privacy: .public)s). Entering standby power saving.")
                self.enterPowerSaving(isStandby: true, reason: "InactivityTimeout")
                return
            }

            guard !self.isPowerSaving else { return }

            self.heartbeatInFlight = true
            self.ioQueue.async { [weak self] in
                guard let self = self else { return }
                defer {
                    DispatchQueue.main.async {
                        self.heartbeatInFlight = false
                    }
                }
                if let heartbeatReport = try? VibeKeyPacketBuilder.heartbeatReport() {
                    _ = try? self.sendReportSync(heartbeatReport, to: device)
                }
            }
        }
        heartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func startPeriodicPolling() {
        pollTimer?.invalidate()
        let generation = self.onlineGeneration

        // Periodically refresh battery every 180 seconds (3 minutes) to avoid battery drain over RF
        let timer = Timer(timeInterval: 180.0, repeats: true) { [weak self] _ in
            guard let self = self, self.onlineGeneration == generation, !self.isPowerSaving else { return }
            self.queryBattery()
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimers() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        heartbeatInFlight = false
    }
}
