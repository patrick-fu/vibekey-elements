import AppKit
import Foundation
import VibeKeyCore

final class SettingsViewController: NSViewController {
    var onConfigurationChanged: ((VibeKeyConfiguration) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var onQuitRequested: (() -> Void)?

    private var config: VibeKeyConfiguration
    private var currentSnapshot: VibeKeyDeviceInfoSnapshot

    private let titleLabel = NSTextField(labelWithString: "VibeKey Elements")
    private let statusLabel = NSTextField(labelWithString: "正在检测设备...")
    private let hardwareInfoLabel = NSTextField(labelWithString: "")
    private let batteryLabel = NSTextField(labelWithString: "")

    private var popupButtons: [InputControl: NSPopUpButton] = [:]

    init(config: VibeKeyConfiguration, snapshot: VibeKeyDeviceInfoSnapshot) {
        self.config = config
        self.currentSnapshot = snapshot
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 410))

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)

        let subtitleLabel = NSTextField(labelWithString: "优篮子 Ulanzi AU05 · 轻量原生控制器")
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        batteryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        hardwareInfoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hardwareInfoLabel.textColor = .secondaryLabelColor

        let infoBox = NSBox()
        infoBox.title = "硬件状态"
        infoBox.titleFont = .systemFont(ofSize: 11, weight: .medium)
        let infoStack = NSStackView(views: [statusLabel, batteryLabel, hardwareInfoLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 5
        infoBox.contentView = infoStack

        let mappingGrid = makeMappingGrid()

        let refreshBtn = NSButton(title: "刷新信息", target: self, action: #selector(handleRefreshClicked))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = .systemFont(ofSize: 12)

        let quitBtn = NSButton(title: "退出", target: self, action: #selector(handleQuitClicked))
        quitBtn.bezelStyle = .rounded
        quitBtn.font = .systemFont(ofSize: 12)

        let bottomStack = NSStackView(views: [refreshBtn, NSView(), quitBtn])
        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY

        let mainStack = NSStackView(views: [
            titleLabel,
            subtitleLabel,
            infoBox,
            mappingGrid,
            bottomStack
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
            infoBox.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            mappingGrid.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        self.view = root
        updateUI()
    }

    private func makeMappingGrid() -> NSGridView {
        let controls: [InputControl] = [
            .topButton,
            .middleButton,
            .bottomButton,
            .knobLeft,
            .knobRight,
            .knobPress
        ]

        var rows: [[NSView]] = []
        for control in controls {
            let label = NSTextField(labelWithString: control.displayName)
            label.font = .systemFont(ofSize: 12, weight: .medium)

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = .systemFont(ofSize: 12)
            popup.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
            popup.target = self
            popup.action = #selector(handleMappingSelectionChanged(_:))

            for preset in PresetAction.allCases {
                let item = NSMenuItem(title: preset.displayName, action: nil, keyEquivalent: "")
                item.representedObject = preset
                popup.menu?.addItem(item)
            }

            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            popupButtons[control] = popup
            rows.append([label, popup])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 7
        grid.columnSpacing = 14
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    func updateState(config: VibeKeyConfiguration, snapshot: VibeKeyDeviceInfoSnapshot) {
        self.config = config
        self.currentSnapshot = snapshot
        if isViewLoaded {
            updateUI()
        }
    }

    private func updateUI() {
        if currentSnapshot.isConnected {
            statusLabel.stringValue = "● 设备已连接 (优篮子 AU05)"
            statusLabel.textColor = .systemGreen

            if let b = currentSnapshot.battery {
                let bolt = b.isCharging ? "⚡ (充电中)" : "(电池供电)"
                batteryLabel.stringValue = "电量: \(b.percent)% \(bolt)  ·  电压: \(b.voltageMillivolts) mV"
                batteryLabel.textColor = b.isCharging ? .systemOrange : .labelColor
            } else {
                batteryLabel.stringValue = "电量: 获取中..."
                batteryLabel.textColor = .secondaryLabelColor
            }

            let fw = currentSnapshot.firmwareVersion ?? "读取中..."
            let sn = currentSnapshot.serialNumber ?? "读取中..."
            hardwareInfoLabel.stringValue = "固件: \(fw)  |  SN: \(sn)"
        } else {
            statusLabel.stringValue = "○ 设备未连接 (Offline)"
            statusLabel.textColor = .systemGray
            batteryLabel.stringValue = "电量: —"
            batteryLabel.textColor = .secondaryLabelColor
            hardwareInfoLabel.stringValue = "请插入 2.4G 接收器或通过 USB 连接"
        }

        // Update popup selections & checkmark states
        for (control, popup) in popupButtons {
            let action = config.action(for: control)
            let matchingPreset = PresetAction.allCases.first(where: { $0.actionConfig == action }) ?? .none
            for item in popup.itemArray {
                if let preset = item.representedObject as? PresetAction {
                    item.state = (preset == matchingPreset) ? .on : .off
                }
            }
            if let matchingItem = popup.itemArray.first(where: { ($0.representedObject as? PresetAction) == matchingPreset }) {
                popup.select(matchingItem)
            }
        }
    }

    @objc private func handleMappingSelectionChanged(_ sender: NSPopUpButton) {
        guard let rawId = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawId),
              let preset = sender.selectedItem?.representedObject as? PresetAction else {
            return
        }

        config.setAction(preset.actionConfig, for: control)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleRefreshClicked() {
        onRefreshRequested?()
    }

    @objc private func handleQuitClicked() {
        onQuitRequested?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsVC: SettingsViewController?
    private var flashTimer: Timer?

    private var config = VibeKeyConfiguration()
    private var currentSnapshot = VibeKeyDeviceInfoSnapshot()

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfiguration()
        setupStatusItem()
        setupPopover()
        setupHIDListeners()

        if !VibeKeyHIDManager.hasInputMonitoringAccess() {
            VibeKeyHIDManager.requestInputMonitoringAccess()
        }

        VibeKeyHIDManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        VibeKeyHIDManager.shared.stop()
    }

    private func loadConfiguration() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "VibeKeyElementsConfig"),
           let saved = try? JSONDecoder().decode(VibeKeyConfiguration.self, from: data) {
            config = saved
        }
    }

    private func saveConfiguration() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "VibeKeyElementsConfig")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item
        updateStatusItemDisplay()
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true

        let vc = SettingsViewController(config: config, snapshot: currentSnapshot)
        vc.onConfigurationChanged = { [weak self] newConfig in
            guard let self = self else { return }
            self.config = newConfig
            self.saveConfiguration()
        }
        vc.onRefreshRequested = {
            VibeKeyHIDManager.shared.refreshDeviceInfo()
        }
        vc.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }

        pop.contentViewController = vc
        self.popover = pop
        self.settingsVC = vc
    }

    @objc private func handleStatusItemClicked(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent
        if currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            VibeKeyHIDManager.shared.refreshDeviceInfo()
            settingsVC?.updateState(config: config, snapshot: currentSnapshot)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()

        // 1. Device Info Header
        let statusTitle = currentSnapshot.isConnected ? "优篮子 AU05 (已连接)" : "优篮子 AU05 (离线)"
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if let fw = currentSnapshot.firmwareVersion {
            let fwItem = NSMenuItem(title: "固件版本: \(fw)", action: nil, keyEquivalent: "")
            fwItem.isEnabled = false
            menu.addItem(fwItem)
        }
        if let sn = currentSnapshot.serialNumber {
            let snItem = NSMenuItem(title: "序列号: \(sn)", action: nil, keyEquivalent: "")
            snItem.isEnabled = false
            menu.addItem(snItem)
        }
        if let b = currentSnapshot.battery {
            let charge = b.isCharging ? "⚡ 充电中" : "电池供电"
            let batteryItem = NSMenuItem(title: "电量: \(b.percent)% (\(charge), \(b.voltageMillivolts)mV)", action: nil, keyEquivalent: "")
            batteryItem.isEnabled = false
            menu.addItem(batteryItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Open Settings Window
        menu.addItem(NSMenuItem(title: "打开控制面板…", action: #selector(handleOpenPopover), keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        // 3. Key Mappings with explicit current Checkmarks
        let keysMenu = NSMenu()
        let controls: [InputControl] = [.topButton, .middleButton, .bottomButton, .knobLeft, .knobRight, .knobPress]
        for control in controls {
            let sub = NSMenu()
            let currentAction = config.action(for: control)
            for preset in PresetAction.allCases {
                let item = NSMenuItem(title: preset.displayName, action: #selector(handleMenuSetKeyAction(_:)), keyEquivalent: "")
                item.representedObject = (control, preset)
                item.state = (preset.actionConfig == currentAction) ? .on : .off
                sub.addItem(item)
            }
            let parent = NSMenuItem(title: control.displayName, action: nil, keyEquivalent: "")
            parent.submenu = sub
            keysMenu.addItem(parent)
        }
        let keysParent = NSMenuItem(title: "按键映射", action: nil, keyEquivalent: "")
        keysParent.submenu = keysMenu
        menu.addItem(keysParent)

        // 4. Noise Reduction with explicit Checkmarks
        let nrMenu = NSMenu()
        for level in 0...3 {
            let label: String
            switch level {
            case 0: label = "关闭 (0)"
            case 1: label = "低 (1)"
            case 2: label = "中 (2)"
            case 3: label = "高 (3)"
            default: label = "\(level)"
            }
            let item = NSMenuItem(title: label, action: #selector(handleSetNR(_:)), keyEquivalent: "")
            item.tag = level
            nrMenu.addItem(item)
        }
        let nrParent = NSMenuItem(title: "麦克风降噪", action: nil, keyEquivalent: "")
        nrParent.submenu = nrMenu
        menu.addItem(nrParent)

        // 5. LED Illumination
        let ledMenu = NSMenu()
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.rawValue.capitalized, action: #selector(handleSetLED(_:)), keyEquivalent: "")
            item.representedObject = mode
            ledMenu.addItem(item)
        }
        let ledParent = NSMenuItem(title: "指示灯模式", action: nil, keyEquivalent: "")
        ledParent.submenu = ledMenu
        menu.addItem(ledParent)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 VibeKey Elements", action: #selector(handleQuit), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func handleOpenPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        VibeKeyHIDManager.shared.refreshDeviceInfo()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func handleMenuSetKeyAction(_ sender: NSMenuItem) {
        guard let (control, preset) = sender.representedObject as? (InputControl, PresetAction) else { return }
        config.setAction(preset.actionConfig, for: control)
        saveConfiguration()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
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

    private func updateStatusItemDisplay(overrideText: String? = nil) {
        guard let button = statusItem?.button else { return }

        // 1. Native SF Symbol template icon with standard spacing
        let iconName = currentSnapshot.isConnected ? "dial.medium.fill" : "dial.medium"
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: "VibeKey") {
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeft
        }

        // 2. Clear key flash feedback
        if let override = overrideText {
            let attr = NSAttributedString(
                string: " \(override)",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .bold),
                    .foregroundColor: NSColor.controlAccentColor
                ]
            )
            button.attributedTitle = attr
            return
        }

        // 3. Clean status bar typography (clean spacing, monospaced digits, no squeezed emojis)
        if !currentSnapshot.isConnected {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "优篮子 AU05 (未连接)"
            return
        }

        if let battery = currentSnapshot.battery {
            let bolt = battery.isCharging ? " ⚡" : ""
            let text = " \(battery.percent)%\(bolt)"
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .medium)
                ]
            )
            button.attributedTitle = attr
            let chargeState = battery.isCharging ? "充电中" : "电池供电"
            button.toolTip = "优篮子 AU05 · 电量 \(battery.percent)% (\(chargeState), \(battery.voltageMillivolts)mV)"
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "优篮子 AU05 (已连接)"
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
            self.currentSnapshot.isConnected = true
            self.updateStatusItemDisplay()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }

        VibeKeyHIDManager.shared.onDeviceDisconnected = { [weak self] in
            guard let self = self else { return }
            self.currentSnapshot = VibeKeyDeviceInfoSnapshot(isConnected: false)
            self.updateStatusItemDisplay()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }

        VibeKeyHIDManager.shared.onDeviceInfoUpdated = { [weak self] snapshot in
            guard let self = self else { return }
            self.currentSnapshot = snapshot
            self.updateStatusItemDisplay()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }

        VibeKeyHIDManager.shared.onBatteryUpdated = { [weak self] battery in
            guard let self = self else { return }
            self.currentSnapshot.battery = battery
            self.updateStatusItemDisplay()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }

        VibeKeyHIDManager.shared.onEventReceived = { [weak self] control, phase in
            guard let self = self else { return }
            if phase == .down {
                self.triggerKeyFlash(control.displayLabel)
                let action = self.config.action(for: control)
                ActionPerformer.perform(action)
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
