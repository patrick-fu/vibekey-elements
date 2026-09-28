import Foundation
import IOKit
import IOKit.hid
import VibeKeyCore

final class CLIInputContext {
    let handler: ([UInt8], UInt32) -> Void
    init(handler: @escaping ([UInt8], UInt32) -> Void) { self.handler = handler }
}

final class CLIReadbackBox {
    var collector = VibeKeyReadbackCollector()
}

final class CLIDeviceSession {
    let manager: IOHIDManager
    let device: IOHIDDevice
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var inputCapacity = 64
    private var inputContextRef: Unmanaged<CLIInputContext>?

    init?(manager: IOHIDManager, device: IOHIDDevice) {
        self.manager = manager
        self.device = device
    }

    static func open() -> CLIDeviceSession? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: VibeKeyDeviceInfo.vendorID,
            kIOHIDProductIDKey as String: VibeKeyDeviceInfo.productID,
            kIOHIDPrimaryUsagePageKey as String: VibeKeyDeviceInfo.usagePage,
            kIOHIDPrimaryUsageKey as String: VibeKeyDeviceInfo.usage
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            return nil
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = deviceSet.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDDeviceScheduleWithRunLoop(
            device,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        return CLIDeviceSession(manager: manager, device: device)
    }

    func beginInput(_ handler: @escaping ([UInt8], UInt32) -> Void) {
        let capacity = 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        let context = CLIInputContext(handler: handler)
        inputContextRef = Unmanaged.passRetained(context)
        let contextPointer = inputContextRef!.toOpaque()

        let callback: IOHIDReportCallback = { rawContext, result, _, _, reportID, report, length in
            guard result == kIOReturnSuccess, let rawContext = rawContext, length > 0 else { return }
            let context = Unmanaged<CLIInputContext>.fromOpaque(rawContext).takeUnretainedValue()
            context.handler([UInt8](UnsafeBufferPointer(start: report, count: length)), reportID)
        }

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            capacity,
            callback,
            contextPointer
        )
        inputBuffer = buffer
        inputCapacity = capacity
    }

    /// Runs the HID run loop until `condition` is true or the timeout expires.
    @discardableResult
    func waitForInput(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    func runForever() {
        while true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
    }

    func sendReport(_ reportBytes: [UInt8]) -> Bool {
        var buffer = reportBytes
        let status = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(VibeKeyDeviceInfo.reportID),
            &buffer,
            buffer.count
        )
        return status == kIOReturnSuccess
    }

    deinit {
        if let buffer = inputBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, inputCapacity, nil, nil)
            buffer.deinitialize(count: inputCapacity)
            buffer.deallocate()
        }
        inputContextRef?.release()
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

struct CLIHelper {
    static func printUsage() {
        print("""
        VibeKey Elements CLI (vibekey) v0.1.0
        The ultimate developer-oriented hub for Ulanzi VibeKey (AU05).

        USAGE:
          vibekey <command> [arguments]

        COMMANDS:
          status                           Connect, read hardware status, and print it
          config                           Print the JSON config path and configuration
          monitor                          Stream keys, knobs, notices, and status responses
          set-nr <0-3>                     Set microphone hardware noise reduction level
          set-standby <seconds>            Set standby delay (e.g. 1800 for 30m, 0 for never)
          set-sleep <seconds>              Set deep sleep delay (e.g. 3600 for 1h)
          led <0-3> <mode> [brightness]    Control LED (modes: solid, breathing, off, auto; brightness: 0-100)
          reset-led                        Reset LED to default hardware control
          hook <state>                     Trigger AI Agent state (thinking, working, error, idle)
          reboot                           Soft reboot AU05 hardware
          reset-hardware                   Reset all device hardware settings to factory defaults
          help                             Show this help message

        EXAMPLES:
          vibekey status
          vibekey set-nr 2
          vibekey set-standby 1800
          vibekey led 0 breathing 80
          vibekey hook thinking
          vibekey hook idle
        """)
    }
}

let args = CommandLine.arguments

guard args.count > 1 else {
    CLIHelper.printUsage()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "help", "-h", "--help":
    CLIHelper.printUsage()
    exit(0)

case "config":
    let url = VibeKeyConfigurationFile.defaultURL
    let configuration = (try? VibeKeyConfigurationFile.load()) ?? VibeKeyConfiguration()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(configuration)
    print("Config file: \(url.path)\(FileManager.default.fileExists(atPath: url.path) ? "" : " (default, not created)")")
    print(String(decoding: data, as: UTF8.self))

case "status":
    print("🔍 Looking for Ulanzi AU05...")
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found or cannot be opened. Ensure the dongle is connected and Input Monitoring is granted.")
        exit(1)
    }
    print("✅ VibeKey dongle connected! (VID: 0x\(String(VibeKeyDeviceInfo.vendorID, radix: 16)), PID: 0x\(String(VibeKeyDeviceInfo.productID, radix: 16)))")

    let box = CLIReadbackBox()
    session.beginInput { bytes, reportID in
        guard let plaintext = try? TEACodec.decryptInputReport(
            bytes,
            hasReportID: reportID == UInt32(VibeKeyDeviceInfo.reportID)
        ) else { return }
        if let observation = box.collector.ingest(plaintext: plaintext) {
            print("↳ \(VibeKeyReadbackCollector.display(observation))")
        }
    }

    let queries: [[UInt8]] = [
        (try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02)) ?? [],
        (try? VibeKeyPacketBuilder.firmwareVersionQueryReport()) ?? [],
        (try? VibeKeyPacketBuilder.serialNumberQueryReport()) ?? [],
        (try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x2C)) ?? [],
        (try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x42)) ?? [],
        (try? VibeKeyPacketBuilder.noiseReductionQueryReport()) ?? [],
        (try? VibeKeyPacketBuilder.microphoneEnableQueryReport()) ?? []
    ].filter { !$0.isEmpty }
    for query in queries where !box.collector.isQueryStatusComplete {
        _ = session.sendReport(query)
        usleep(25_000)
    }

    let complete = session.waitForInput(timeout: 2.0) { box.collector.isQueryStatusComplete }
    print("\n\(box.collector.statusSummary())")
    if !complete {
        print("⚠️ Some fields did not answer before the 2s timeout.")
    }

case "monitor":
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found or cannot be opened.")
        exit(1)
    }
    print("👂 Monitoring VibeKey events. Press Control-C to stop.")
    let box = CLIReadbackBox()
    session.beginInput { bytes, reportID in
        guard let plaintext = try? TEACodec.decryptInputReport(
            bytes,
            hasReportID: reportID == UInt32(VibeKeyDeviceInfo.reportID)
        ), let observation = box.collector.ingest(plaintext: plaintext) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(VibeKeyReadbackCollector.display(observation))")
    }
    for report in [
        try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02),
        try? VibeKeyPacketBuilder.firmwareVersionQueryReport(),
        try? VibeKeyPacketBuilder.serialNumberQueryReport()
    ].compactMap({ $0 }) {
        _ = session.sendReport(report)
        usleep(25_000)
    }
    session.runForever()

case "set-nr":
    guard args.count > 2, let level = UInt8(args[2]), level <= 3 else {
        print("❌ Invalid NR level. Choose 0 (Off), 1 (Low), 2 (Medium), or 3 (High).")
        exit(1)
    }
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.setNoiseReductionReport(level: level) {
        if session.sendReport(report) {
            print("✅ Microphone noise reduction set to level \(level).")
        } else {
            print("❌ Failed to set noise reduction.")
            exit(1)
        }
    }

case "set-standby":
    guard args.count > 2, let seconds = UInt32(args[2]) else {
        print("❌ Usage: vibekey set-standby <seconds>")
        exit(1)
    }
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.setStandbyTimeoutReport(seconds: seconds) {
        if session.sendReport(report) {
            print("✅ Standby timeout set to \(seconds)s.")
        } else {
            print("❌ Failed to set standby timeout.")
            exit(1)
        }
    }

case "set-sleep":
    guard args.count > 2, let seconds = UInt32(args[2]) else {
        print("❌ Usage: vibekey set-sleep <seconds>")
        exit(1)
    }
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.setSleepTimeoutReport(seconds: seconds) {
        if session.sendReport(report) {
            print("✅ Deep sleep timeout set to \(seconds)s.")
        } else {
            print("❌ Failed to set sleep timeout.")
            exit(1)
        }
    }

case "led":
    guard args.count > 3, let channel = UInt8(args[2]), channel <= 3,
          let mode = LEDMode(rawValue: args[3].lowercased()) else {
        print("❌ Usage: vibekey led <channel 0-3> <solid|breathing|off|auto> [brightness 0-100]")
        exit(1)
    }
    let brightness = args.count > 4 ? (UInt8(args[4]) ?? 100) : 100
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: channel, mode: mode, brightness: brightness) {
        if session.sendReport(report) {
            print("✅ LED channel \(channel) set to \(mode.rawValue) (brightness: \(brightness)).")
        } else {
            print("❌ Failed to send LED report.")
            exit(1)
        }
    }

case "reset-led":
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.resetLEDReport() {
        if session.sendReport(report) {
            print("✅ LED reset to default hardware control.")
        } else {
            print("❌ Failed to reset LED.")
            exit(1)
        }
    }

case "hook":
    guard args.count > 2, let state = AgentHookState(rawValue: args[2].lowercased()) else {
        print("❌ Usage: vibekey hook <thinking|working|error|idle>")
        exit(1)
    }
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    var success = false
    switch state {
    case .thinking:
        if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .breathing, brightness: 80) {
            success = session.sendReport(report)
        }
        print(success ? "🤖 [AI Hook] State: THINKING (LED breathing)" : "❌ Failed to send hook state")
    case .working:
        if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .solid, brightness: 100) {
            success = session.sendReport(report)
        }
        print(success ? "🤖 [AI Hook] State: WORKING (LED solid active)" : "❌ Failed to send hook state")
    case .error:
        if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .breathing, brightness: 100) {
            success = session.sendReport(report)
        }
        print(success ? "🚨 [AI Hook] State: ERROR (LED alert)" : "❌ Failed to send hook state")
    case .idle:
        if let report = try? VibeKeyPacketBuilder.resetLEDReport() {
            success = session.sendReport(report)
        }
        print(success ? "💤 [AI Hook] State: IDLE (LED auto)" : "❌ Failed to send hook state")
    }

case "reboot":
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    if let report = try? VibeKeyPacketBuilder.rebootReport() {
        if session.sendReport(report) {
            print("✅ Reboot command sent to device.")
        } else {
            print("❌ Failed to send reboot command.")
            exit(1)
        }
    }

case "reset-hardware":
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found.")
        exit(1)
    }
    print("🔄 Resetting hardware settings to factory defaults...")
    if let rep = try? VibeKeyPacketBuilder.setHooksModeReport(enabled: false) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.setAudioButtonSystemModeReport(enabled: false) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.resetLEDReport() { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.setNoiseReductionReport(level: 0) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.setMicrophoneEnableReport(enabled: true) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.setStandbyTimeoutReport(seconds: 300) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.setSleepTimeoutReport(seconds: 3600) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.softwareOnlineReport(true) { _ = session.sendReport(rep) }
    usleep(25_000)
    if let rep = try? VibeKeyPacketBuilder.heartbeatReport() { _ = session.sendReport(rep) }
    print("✅ All hardware parameters restored to factory defaults (NR=0, Mic=On, LED=Auto, Standby=300s, Sleep=3600s, Hooks=0).")

default:
    print("❌ Unknown command: \(command)")
    CLIHelper.printUsage()
    exit(1)
}
