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
    private var isStarted = false

    // Persistent heap buffer for IOHID input report callback
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportCapacity = 64

    public var onDeviceConnected: (() -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onBatteryUpdated: ((VibeKeyBatteryStatus) -> Void)?
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
        stopHeartbeat()

        if let device = connectedDevice {
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

        // Proactively discover devices already attached before app launch
        if let existingDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
           let device = existingDevices.first {
            handleDeviceMatched(device)
        }
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        guard connectedDevice == nil else { return }
        connectedDevice = device

        attachInputDevice(device)

        self.onDeviceConnected?()

        // Handshake: Reset to native baseline first, then activate online mode and heartbeat
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            // 1. Reset offline
            if let offlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(false) {
                _ = try? self.sendReportSync(offlineReport, to: device)
            }
            usleep(80_000) // 80ms baseline rest

            // 2. Enable host-online mode
            if let onlineReport = try? VibeKeyPacketBuilder.softwareOnlineReport(true) {
                _ = try? self.sendReportSync(onlineReport, to: device)
            }

            DispatchQueue.main.async {
                self.startHeartbeat()
                self.queryBattery()
            }
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard let current = connectedDevice, current === device else { return }
        stopHeartbeat()
        detachInputDevice(device)
        connectedDevice = nil
        onDeviceDisconnected?()
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

        self.inputReportBuffer = buffer
        self.inputReportCapacity = capacity
    }

    private func detachInputDevice(_ device: IOHIDDevice) {
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
                }
            }
            return
        }

        // 2. Check for power / battery responses
        if let powerResp = VibeKeyParser.parsePowerResponse(plaintext: plaintext) {
            if case let .battery(status) = powerResp {
                DispatchQueue.main.async {
                    self.onBatteryUpdated?(status)
                }
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

    public func queryBattery() {
        guard let report = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02) else { return }
        try? sendCommand(report)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let report = try? VibeKeyPacketBuilder.heartbeatReport() else { return }
            try? self.sendCommand(report)
        }
        heartbeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
}
