import Foundation
import IOKit
import IOKit.hid
import VibeKeyCore

final class CLIDeviceSession {
    let manager: IOHIDManager
    let device: IOHIDDevice

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

        return CLIDeviceSession(manager: manager, device: device)
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
          status                           Check hardware connection and send battery query
          set-nr <0-3>                     Set microphone hardware noise reduction level
          set-standby <seconds>            Set standby delay (e.g. 1800 for 30m, 0 for never)
          set-sleep <seconds>              Set deep sleep delay (e.g. 3600 for 1h)
          led <0-3> <mode> [brightness]    Control LED (modes: solid, breathing, off, auto; brightness: 0-100)
          reset-led                        Reset LED to default hardware control
          hook <state>                     Trigger AI Agent state (thinking, working, error, idle)
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

case "status":
    print("🔍 Looking for Ulanzi AU05...")
    guard let session = CLIDeviceSession.open() else {
        print("❌ Device not found or cannot be opened. Ensure VibeKey is connected via USB.")
        exit(1)
    }
    print("✅ VibeKey connected! (VID: 0x\(String(VibeKeyDeviceInfo.vendorID, radix: 16)), PID: 0x\(String(VibeKeyDeviceInfo.productID, radix: 16)))")
    if let report = try? VibeKeyPacketBuilder.powerQueryReport(commandID: 0x02) {
        if session.sendReport(report) {
            print("⚡ Battery status query report sent successfully.")
        } else {
            print("⚠️ Failed to transmit query report to device.")
        }
    }

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

default:
    print("❌ Unknown command: \(command)")
    CLIHelper.printUsage()
    exit(1)
}
