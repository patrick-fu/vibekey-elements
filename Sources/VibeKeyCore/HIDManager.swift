import Foundation
import IOKit
import IOKit.hid

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
    private var heartbeatTimer: DispatchSourceTimer?
    private var isStarted = false

    // Persistent heap buffer for IOHID input report callback (prevents dangling pointer UAF)
    private let reportBufferSize = 64
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?

    public var onDeviceConnected: (() -> Void)?
    public var onDeviceDisconnected: (() -> Void)?
    public var onBatteryUpdated: ((VibeKeyBatteryStatus) -> Void)?
    public var onEventReceived: ((InputControl, ButtonPhase) -> Void)?

    private let ioQueue = DispatchQueue(label: "com.patrickfu.vibekey.hid", qos: .userInitiated)

    public init() {
        self.inputReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
        self.inputReportBuffer?.initialize(repeating: 0, count: reportBufferSize)
    }

    deinit {
        stop()
        if let buffer = inputReportBuffer {
            buffer.deallocate()
            inputReportBuffer = nil
        }
    }

    public func start() {
        ioQueue.async {
            guard !self.isStarted else { return }
            self.isStarted = true
            self.setupHIDManager()
        }
    }

    public func stop() {
        ioQueue.sync {
            guard self.isStarted else { return }
            self.isStarted = false
            self.stopHeartbeat()

            if let device = self.connectedDevice, let bufferPtr = self.inputReportBuffer {
                _ = try? self.sendReportSync(VibeKeyPacketBuilder.softwareOnlineReport(false), to: device)
                IOHIDDeviceRegisterInputReportCallback(device, bufferPtr, self.reportBufferSize, nil, nil)
            }

            if let manager = self.hidManager {
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }

            self.hidManager = nil
            self.connectedDevice = nil
        }
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
            guard let context = context else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            instance.ioQueue.async {
                instance.handleDeviceMatched(device)
            }
        }

        let removalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            guard let context = context else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            instance.ioQueue.async {
                instance.handleDeviceRemoved(device)
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, matchingCallback, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, removalCallback, selfPtr)

        IOHIDManagerSetDispatchQueue(manager, ioQueue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        self.connectedDevice = device
        guard let bufferPtr = self.inputReportBuffer else { return }

        let reportCallback: IOHIDReportCallback = { context, result, sender, type, reportID, report, length in
            guard let context = context, length > 0 else { return }
            let instance = Unmanaged<VibeKeyHIDManager>.fromOpaque(context).takeUnretainedValue()
            let bytes = [UInt8](UnsafeBufferPointer(start: report, count: length))
            instance.handleInputReport(reportID: reportID, bytes: bytes)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            bufferPtr,
            reportBufferSize,
            reportCallback,
            selfPtr
        )

        DispatchQueue.main.async {
            self.onDeviceConnected?()
        }

        // Wait 1.2s handshake delay before entering software-online mode
        ioQueue.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, self.connectedDevice === device else { return }
            _ = try? self.sendReportSync(VibeKeyPacketBuilder.softwareOnlineReport(true), to: device)
            self.startHeartbeat()
            self.queryBattery()
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        if self.connectedDevice === device {
            if let bufferPtr = self.inputReportBuffer {
                IOHIDDeviceRegisterInputReportCallback(device, bufferPtr, self.reportBufferSize, nil, nil)
            }
            self.connectedDevice = nil
            stopHeartbeat()
            DispatchQueue.main.async {
                self.onDeviceDisconnected?()
            }
        }
    }

    private func handleInputReport(reportID: UInt32, bytes: [UInt8]) {
        let hasExplicitID = (reportID == UInt32(VibeKeyDeviceInfo.reportID))
        guard let plaintext = try? TEACodec.decryptInputReport(bytes, hasReportID: hasExplicitID) else { return }

        // 1. Check for physical events
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
        try ioQueue.sync {
            guard let device = self.connectedDevice else {
                throw VibeKeyHIDError.deviceNotConnected
            }
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
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, let report = try? VibeKeyPacketBuilder.heartbeatReport() else { return }
            try? self.sendCommand(report)
        }
        timer.resume()
        self.heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }
}
