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

public final class VibeKeyHIDManager: @unchecked Sendable {
    public static let shared = VibeKeyHIDManager()

    private var hidManager: IOHIDManager?
    private var connectedDevice: IOHIDDevice?
    private var heartbeatTimer: Timer?
    private var pollTimer: Timer?
    private var isStarted = false

    // State guards & counters
    private var heartbeatInFlight = false
    private var onlineGeneration: UInt64 = 0

    // Persistent heap buffer for IOHID input report callback
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportCapacity = 64

    // Serial number chunks collector
    private var snChunks: [Int: String] = [:]

    // Current snapshot
    public private(set) var currentSnapshot = VibeKeyDeviceInfoSnapshot()

    public var onDeviceConnected: (() -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onBatteryUpdated: ((VibeKeyBatteryStatus) -> Void)?
    public var onDeviceInfoUpdated: ((VibeKeyDeviceInfoSnapshot) -> Void)?
    public var onEventReceived: ((InputControl, ButtonPhase) -> Void)?

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
        currentSnapshot = VibeKeyDeviceInfoSnapshot()
    }

    private func setupHIDManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: VibeKeyDeviceInfo.vendorID,
            kIOHIDProductIDKey as String: VibeKeyDeviceInfo.productID,
            kIOHIDPrimaryUsagePageKey as String: VibeKeyDeviceInfo.usagePage,
            kIOHIDPrimaryUsageKey as String: VibeKeyDeviceInfo.usage
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

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
            return
        }

        // Check if device is already plugged in
        if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
           let device = existingDevices.first {
            handleDeviceMatched(device)
        }
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        guard connectedDevice == nil else { return }
        connectedDevice = device

        attachInputDevice(device)
        currentSnapshot.isConnected = true
        snChunks.removeAll()
        onlineGeneration &+= 1

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
                guard self.onlineGeneration == generation else { return }
                self.startHeartbeat()
                self.startPeriodicPolling()
                self.refreshDeviceInfo()
            }
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard let current = connectedDevice, current === device else { return }
        stopTimers()
        detachInputDevice(device)
        connectedDevice = nil
        onlineGeneration &+= 1
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

    private func handleInputReport(reportID: UInt32, bytes: [UInt8]) {
        let hasExplicitID = (reportID == UInt32(VibeKeyDeviceInfo.reportID))
        guard let plaintext = try? TEACodec.decryptInputReport(bytes, hasReportID: hasExplicitID) else { return }

        // 1. Check for physical events (K1, K2, K3, Knob)
        if let event = VibeKeyParser.parseDeviceEvent(plaintext: plaintext) {
            if case let .key(control, phase) = event {
                DispatchQueue.main.async {
                    self.onEventReceived?(control, phase)
                    // If device was in standby, mark active
                    if self.currentSnapshot.isStandby {
                        self.currentSnapshot.isStandby = false
                        self.onDeviceInfoUpdated?(self.currentSnapshot)
                    }
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
                switch notice {
                case let .standby(isStandby):
                    self.currentSnapshot.isStandby = isStandby
                case let .active(isActive):
                    self.currentSnapshot.isStandby = !isActive
                case .powerOn:
                    self.currentSnapshot.isStandby = false
                    self.refreshDeviceInfo()
                }
                self.onDeviceInfoUpdated?(self.currentSnapshot)
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
                case let .sleepTime(sec):
                    self.currentSnapshot.sleepTimeSeconds = sec
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
        guard let device = connectedDevice else { return }
        ioQueue.async { [weak self] in
            guard let self = self else { return }
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
        }
    }

    public func queryBattery() {
        guard let device = connectedDevice,
              let report = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02) else { return }
        ioQueue.async { [weak self] in
            _ = try? self?.sendReportSync(report, to: device)
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

        // Periodically refresh battery every 15 seconds to ensure charging / percentage is live
        let timer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self, self.onlineGeneration == generation else { return }
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
