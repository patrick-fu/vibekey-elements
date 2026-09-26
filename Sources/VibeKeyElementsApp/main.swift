import AppKit
import Foundation
import VibeKeyCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var flashTimer: Timer?
    private var currentBatteryStatus: VibeKeyBatteryStatus?
    private var isConnected: Bool = false
    private var config = VibeKeyConfiguration()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHIDListeners()
        VibeKeyHIDManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VibeKeyHIDManager.shared.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemDisplay()
        rebuildMenu()
    }

    private func updateStatusItemDisplay(overrideText: String? = nil) {
        guard let button = statusItem?.button else { return }

        if let override = overrideText {
            button.title = override
            return
        }

        if !isConnected {
            button.title = "🎙 (Offline)"
            return
        }

        if let battery = currentBatteryStatus {
            let bolt = battery.isCharging ? "⚡" : ""
            button.title = "🎙 \(battery.percent)%\(bolt)"
        } else {
            button.title = "🎙 VibeKey"
        }
    }

    private func triggerKeyFlash(_ label: String) {
        flashTimer?.invalidate()
        updateStatusItemDisplay(overrideText: "[\(label)]")

        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.updateStatusItemDisplay()
        }
    }

    private func setupHIDListeners() {
        VibeKeyHIDManager.shared.onDeviceConnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            self.updateStatusItemDisplay()
            self.rebuildMenu()
        }

        VibeKeyHIDManager.shared.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.currentBatteryStatus = nil
            self.updateStatusItemDisplay()
            self.rebuildMenu()
        }

        VibeKeyHIDManager.shared.onBatteryUpdated = { [weak self] battery in
            guard let self = self else { return }
            self.currentBatteryStatus = battery
            self.updateStatusItemDisplay()
            self.rebuildMenu()
        }

        VibeKeyHIDManager.shared.onEventReceived = { [weak self] control, phase in
            guard let self = self else { return }
            
            // UI Flash on Main Thread, Execution on Background actionQueue
            if phase == .down {
                self.triggerKeyFlash(control.displayLabel)
                let action = self.config.action(for: control)
                ActionPerformer.perform(action)
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // 1. Device Info
        let statusTitle = isConnected ? "Device: Connected (AU05)" : "Device: Disconnected"
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if let battery = currentBatteryStatus {
            let chargeState = battery.isCharging ? "Charging" : "Discharging"
            let batteryItem = NSMenuItem(title: "Battery: \(battery.percent)% (\(chargeState), \(battery.voltageMillivolts)mV)", action: nil, keyEquivalent: "")
            batteryItem.isEnabled = false
            menu.addItem(batteryItem)
        }

        // Accessibility Permission Notice
        if !ActionPerformer.hasAccessibilityPermission() {
            let permItem = NSMenuItem(title: "⚠️ Accessibility Permission Required", action: #selector(handleOpenAccessibilitySettings), keyEquivalent: "")
            menu.addItem(permItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Microphone Noise Reduction (NR)
        let nrMenu = NSMenu()
        for level in 0...3 {
            let label: String
            switch level {
            case 0: label = "Off (0)"
            case 1: label = "Low (1)"
            case 2: label = "Medium (2)"
            case 3: label = "High (3)"
            default: label = "\(level)"
            }
            let item = NSMenuItem(title: label, action: #selector(handleSetNR(_:)), keyEquivalent: "")
            item.tag = level
            nrMenu.addItem(item)
        }
        let nrParentItem = NSMenuItem(title: "Mic Noise Reduction", action: nil, keyEquivalent: "")
        nrParentItem.submenu = nrMenu
        menu.addItem(nrParentItem)

        // 3. LED Control
        let ledMenu = NSMenu()
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(handleSetLED(_:)), keyEquivalent: "")
            item.representedObject = mode
            ledMenu.addItem(item)
        }
        let ledParentItem = NSMenuItem(title: "LED Illumination", action: nil, keyEquivalent: "")
        ledParentItem.submenu = ledMenu
        menu.addItem(ledParentItem)

        // 4. Standby Timeout
        let standbyMenu = NSMenu()
        let timeouts: [(String, UInt32)] = [
            ("5 Minutes (Default)", 300),
            ("15 Minutes", 900),
            ("30 Minutes (Recommended)", 1800),
            ("Never Standby", 0)
        ]
        for (title, sec) in timeouts {
            let item = NSMenuItem(title: title, action: #selector(handleSetStandby(_:)), keyEquivalent: "")
            item.tag = Int(sec)
            standbyMenu.addItem(item)
        }
        let standbyParentItem = NSMenuItem(title: "Standby Delay", action: nil, keyEquivalent: "")
        standbyParentItem.submenu = standbyMenu
        menu.addItem(standbyParentItem)

        // 5. AI Agent Hooks Test
        let agentMenu = NSMenu()
        for state in AgentHookState.allCases {
            let item = NSMenuItem(title: state.rawValue.capitalized, action: #selector(handleAgentHook(_:)), keyEquivalent: "")
            item.representedObject = state
            agentMenu.addItem(item)
        }
        let agentParentItem = NSMenuItem(title: "AI Agent Status Hook", action: nil, keyEquivalent: "")
        agentParentItem.submenu = agentMenu
        menu.addItem(agentParentItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VibeKey Elements", action: #selector(handleQuit), keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    @objc private func handleOpenAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func handleSetNR(_ sender: NSMenuItem) {
        let level = UInt8(sender.tag)
        if let report = try? VibeKeyPacketBuilder.setNoiseReductionReport(level: level) {
            try? VibeKeyHIDManager.shared.sendCommand(report)
        }
    }

    @objc private func handleSetLED(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? LEDMode else { return }
        if mode == .auto {
            if let report = try? VibeKeyPacketBuilder.resetLEDReport() {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        } else {
            if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: mode, brightness: 100) {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        }
    }

    @objc private func handleSetStandby(_ sender: NSMenuItem) {
        let seconds = UInt32(sender.tag)
        if let report = try? VibeKeyPacketBuilder.setStandbyTimeoutReport(seconds: seconds) {
            try? VibeKeyHIDManager.shared.sendCommand(report)
        }
    }

    @objc private func handleAgentHook(_ sender: NSMenuItem) {
        guard let state = sender.representedObject as? AgentHookState else { return }
        switch state {
        case .thinking:
            if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .breathing, brightness: 80) {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        case .working:
            if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .solid, brightness: 100) {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        case .error:
            if let report = try? VibeKeyPacketBuilder.setLEDReport(channel: 0, mode: .breathing, brightness: 100) {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        case .idle:
            if let report = try? VibeKeyPacketBuilder.resetLEDReport() {
                try? VibeKeyHIDManager.shared.sendCommand(report)
            }
        }
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
