import Sparkle
import AppKit
import ApplicationServices
import Foundation
import VibeKeyCore

final class SettingsViewController: NSViewController {
    var onConfigurationChanged: ((VibeKeyConfiguration) -> Void)?
    var onRefreshRequested: (() -> Void)?
    var onResetHardwareRequested: (() -> Void)?
    var onResetKeysRequested: (() -> Void)?
    var onRebootRequested: (() -> Void)?
    var onCheckUpdatesRequested: (() -> Void)?
    var onQuitRequested: (() -> Void)?
    var onPermissionsUpdated: (([VibeKeyPermissionReport]) -> Void)?

    private var config: VibeKeyConfiguration
    private var currentSnapshot: VibeKeyDeviceInfoSnapshot

    private let titleLabel = NSTextField(labelWithString: "VibeKey Elements")
    private let subtitleLabel = NSTextField(labelWithString: "优篮子 AU05 轻量原生控制器")
    private let statusLabel = NSTextField(labelWithString: "正在检测设备...")
    private let hardwareInfoLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")

    private var popupButtons: [InputControl: NSPopUpButton] = [:]
    private var customButtons: [InputControl: NSButton] = [:]
    private var permissionStatusLabels: [VibeKeyPermission: NSTextField] = [:]
    private var permissionButtons: [VibeKeyPermission: NSButton] = [:]
    private var permissionRefreshTimers: [Timer] = []
    private var permissionFlowStage: VibeKeyPermission?
    private var activationObserver: NSObjectProtocol?
    private let permissionCenter: VibeKeyPermissionCenter
    private var isLocalPowerSaving: Bool { VibeKeyHIDManager.shared.isPowerSaving }
    private var nrPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var micEnablePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var ledPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var standbyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var sleepPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let longConnectCheckbox = NSButton(checkboxWithTitle: "长连保活（暂停闲置省电）", target: nil, action: nil)

    init(
        config: VibeKeyConfiguration,
        snapshot: VibeKeyDeviceInfoSnapshot,
        permissionCenter: VibeKeyPermissionCenter = VibeKeyPermissionCenter(
            statusProvider: { VibeKeyPermissionCenter.live.statusProvider($0) },
            requestHandler: { VibeKeyPermissionCenter.live.requestHandler($0) },
            settingsOpener: { NSWorkspace.shared.open($0) }
        )
    ) {
        self.config = config
        self.currentSnapshot = snapshot
        self.permissionCenter = permissionCenter
        super.init(nibName: nil, bundle: nil)
        self.preferredContentSize = NSSize(width: 440, height: 736)

        // Returning from System Settings activates this app; TCC has no callback.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        permissionRefreshTimers.forEach { $0.invalidate() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 736))

        // 1. Header
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        hardwareInfoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hardwareInfoLabel.textColor = .secondaryLabelColor
        hardwareInfoLabel.maximumNumberOfLines = 2
        hardwareInfoLabel.lineBreakMode = .byWordWrapping

        permissionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        let headerStack = NSStackView(views: [titleLabel, subtitleLabel, statusLabel, hardwareInfoLabel, permissionLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3

        // 2. System Permission Section
        let permissionHeading = makeSectionHeader("系统授权检测")
        let checkPermissionButton = NSButton(
            title: "一键检测并授权…",
            target: self,
            action: #selector(handleCheckAllPermissionsClicked)
        )
        checkPermissionButton.bezelStyle = .rounded
        checkPermissionButton.font = .systemFont(ofSize: 11)
        let permissionHeadingStack = NSStackView(views: [permissionHeading, NSView(), checkPermissionButton])
        permissionHeadingStack.orientation = .horizontal
        permissionHeadingStack.alignment = .centerY
        permissionHeadingStack.spacing = 8
        let permissionGrid = makePermissionGrid()

        // 3. Mapping Section
        let mappingHeading = makeSectionHeader("按键与旋钮映射")
        let mappingGrid = makeMappingGrid()

        // 4. Hardware Settings Section
        let hardwareHeading = makeSectionHeader("硬件功能调节")
        let hardwareGrid = makeHardwareGrid()

        // 5. Hardware Maintenance Section
        let maintenanceHeading = makeSectionHeader("硬件维护与复位")
        let resetKeysBtn = NSButton(title: "恢复默认按键", target: self, action: #selector(handleResetKeysClicked))
        resetKeysBtn.bezelStyle = .rounded
        resetKeysBtn.font = .systemFont(ofSize: 11)

        let resetHwBtn = NSButton(title: "出厂硬件复位", target: self, action: #selector(handleResetHwClicked))
        resetHwBtn.bezelStyle = .rounded
        resetHwBtn.font = .systemFont(ofSize: 11)

        let rebootBtn = NSButton(title: "重启设备", target: self, action: #selector(handleRebootClicked))
        rebootBtn.bezelStyle = .rounded
        rebootBtn.font = .systemFont(ofSize: 11)

        let maintenanceStack = NSStackView(views: [resetKeysBtn, resetHwBtn, rebootBtn])
        maintenanceStack.orientation = .horizontal
        maintenanceStack.alignment = .centerY
        maintenanceStack.spacing = 8

        // 6. Action Buttons
        let refreshBtn = NSButton(title: "刷新信息", target: self, action: #selector(handleRefreshClicked))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = .systemFont(ofSize: 11)

        let checkUpdateBtn = NSButton(title: "检查更新…", target: self, action: #selector(handleCheckUpdateClicked))
        checkUpdateBtn.bezelStyle = .rounded
        checkUpdateBtn.font = .systemFont(ofSize: 11)

        let quitBtn = NSButton(title: "退出", target: self, action: #selector(handleQuitClicked))
        quitBtn.bezelStyle = .rounded
        quitBtn.font = .systemFont(ofSize: 11)

        let bottomStack = NSStackView(views: [refreshBtn, checkUpdateBtn, NSView(), quitBtn])
        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY
        bottomStack.spacing = 8

        // Separators
        let sep1 = makeSeparator()
        let sep2 = makeSeparator()
        let sep3 = makeSeparator()
        let sep4 = makeSeparator()

        let mainStack = NSStackView(views: [
            headerStack,
            permissionHeadingStack,
            permissionGrid,
            sep1,
            mappingHeading,
            mappingGrid,
            sep2,
            hardwareHeading,
            hardwareGrid,
            sep3,
            maintenanceHeading,
            maintenanceStack,
            sep4,
            bottomStack
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(mainStack)

        // Compression resistance
        headerStack.setContentCompressionResistancePriority(.required, for: .vertical)
        permissionHeadingStack.setContentCompressionResistancePriority(.required, for: .vertical)
        permissionGrid.setContentCompressionResistancePriority(.required, for: .vertical)
        mappingGrid.setContentCompressionResistancePriority(.required, for: .vertical)
        hardwareGrid.setContentCompressionResistancePriority(.required, for: .vertical)
        maintenanceStack.setContentCompressionResistancePriority(.required, for: .vertical)
        bottomStack.setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            mainStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
            headerStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            permissionHeadingStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            permissionGrid.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            sep1.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            mappingHeading.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            mappingGrid.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            sep2.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            hardwareHeading.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            hardwareGrid.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            sep3.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            maintenanceHeading.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            maintenanceStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            sep4.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        self.view = root
        updateUI()
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makePermissionGrid() -> NSGridView {
        var rows: [[NSView]] = []
        for permission in VibeKeyPermission.allCases {
            let nameLabel = NSTextField(labelWithString: permission.displayName)
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)

            let statusLabel = NSTextField(labelWithString: "检测中")
            statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
            statusLabel.toolTip = permission.usageDescription

            let actionButton = NSButton(
                title: "检测并授权…",
                target: self,
                action: #selector(handlePermissionActionClicked(_:))
            )
            actionButton.bezelStyle = .rounded
            actionButton.font = .systemFont(ofSize: 11)
            permissionButtons[permission] = actionButton
            actionButton.toolTip = permission.usageDescription
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true

            permissionStatusLabels[permission] = statusLabel
            rows.append([nameLabel, statusLabel, actionButton])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 5
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 2).xPlacement = .trailing
        return grid
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
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

            // Preserve a visible, checked custom action instead of falsely showing None.
            let customItem = NSMenuItem(title: "自定义动作", action: nil, keyEquivalent: "")
            customItem.representedObject = "custom"
            customItem.identifier = NSUserInterfaceItemIdentifier("vibekey.custom.\(control.rawValue)")
            popup.menu?.addItem(customItem)

            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
            popup.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let customButton = NSButton(title: "自定义…", target: self, action: #selector(handleCustomMappingClicked(_:)))
            customButton.bezelStyle = .rounded
            customButton.font = .systemFont(ofSize: 11)
            customButton.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
            customButtons[control] = customButton
            popupButtons[control] = popup
            let rowStack = NSStackView(views: [popup, customButton])
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 6
            rows.append([label, rowStack])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 5
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func makeHardwareGrid() -> NSGridView {
        // 1. Noise reduction
        let nrLabel = NSTextField(labelWithString: "麦克风硬件降噪")
        nrLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nrPopup.font = .systemFont(ofSize: 12)
        nrPopup.target = self
        nrPopup.action = #selector(handleNRChanged(_:))
        let nrOptions: [(String, UInt8)] = [
            ("关闭 (0 档)", 0),
            ("低降噪 (1 档)", 1),
            ("中降噪 (2 档)", 2),
            ("高降噪 (3 档)", 3)
        ]
        for (name, lvl) in nrOptions {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.tag = Int(lvl)
            nrPopup.menu?.addItem(item)
        }
        nrPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        nrPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 2. Microphone Enable/Mute
        let micLabel = NSTextField(labelWithString: "麦克风收音开关")
        micLabel.font = .systemFont(ofSize: 12, weight: .medium)
        micEnablePopup.font = .systemFont(ofSize: 12)
        micEnablePopup.target = self
        micEnablePopup.action = #selector(handleMicEnableChanged(_:))
        let micOptions: [(String, Int)] = [
            ("开启收音 (默认)", 1),
            ("静音关闭", 0)
        ]
        for (name, val) in micOptions {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.tag = val
            micEnablePopup.menu?.addItem(item)
        }
        micEnablePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        micEnablePopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 3. LED illumination
        let ledLabel = NSTextField(labelWithString: "机身指示灯模式")
        ledLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ledPopup.font = .systemFont(ofSize: 12)
        ledPopup.target = self
        ledPopup.action = #selector(handleLEDChanged(_:))
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: nil, keyEquivalent: "")
            item.representedObject = mode
            ledPopup.menu?.addItem(item)
        }
        ledPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        ledPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 4. Standby delay
        let standbyLabel = NSTextField(labelWithString: "闲置待机时间")
        standbyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        standbyPopup.font = .systemFont(ofSize: 12)
        standbyPopup.target = self
        standbyPopup.action = #selector(handleStandbyChanged(_:))
        let standbyOptions: [(String, UInt32)] = [
            ("5 分钟 (出厂默认)", 300),
            ("15 分钟", 900),
            ("30 分钟 (推荐)", 1800),
            ("从不待机", 0)
        ]
        for (name, sec) in standbyOptions {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.tag = Int(sec)
            standbyPopup.menu?.addItem(item)
        }
        standbyPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        standbyPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 5. Sleep delay
        let sleepLabel = NSTextField(labelWithString: "深度休眠时间")
        sleepLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sleepPopup.font = .systemFont(ofSize: 12)
        sleepPopup.target = self
        sleepPopup.action = #selector(handleSleepChanged(_:))
        let sleepOptions: [(String, UInt32)] = [
            ("30 分钟", 1800),
            ("1 小时 (出厂默认)", 3600),
            ("2 小时", 7200),
            ("4 小时", 14400)
        ]
        for (name, sec) in sleepOptions {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.tag = Int(sec)
            sleepPopup.menu?.addItem(item)
        }
        sleepPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        sleepPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        longConnectCheckbox.font = .systemFont(ofSize: 12)
        longConnectCheckbox.target = self
        longConnectCheckbox.action = #selector(handleLongConnectChanged(_:))

        let grid = NSGridView(views: [
            [nrLabel, nrPopup],
            [micLabel, micEnablePopup],
            [ledLabel, ledPopup],
            [standbyLabel, standbyPopup],
            [sleepLabel, sleepPopup],
            [makeSectionHeader("连接模式"), longConnectCheckbox]
        ])
        grid.rowSpacing = 5
        grid.columnSpacing = 16
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
            let batteryText: String
            if let b = currentSnapshot.battery {
                let charging = b.isCharging ? " ⚡(充电中)" : ""
                batteryText = " · 电量 \(b.percent)%\(charging) [\(b.voltageMillivolts)mV]"
            } else {
                batteryText = " · 电量获取中..."
            }
            if currentSnapshot.isDeviceOn == false {
                statusLabel.stringValue = "● 优篮子 AU05 (已连接 · 设备关机)"
                statusLabel.textColor = .systemGray
                let fw = currentSnapshot.firmwareVersion ?? "未知"
                let sn = currentSnapshot.serialNumber ?? "未知"
                hardwareInfoLabel.stringValue = "固件: \(fw)  |  SN: \(sn)  |  电量为最近缓存"
            } else if isLocalPowerSaving {
                statusLabel.stringValue = "● 优篮子 AU05 (待机省电中)\(batteryText)"
                statusLabel.textColor = .systemOrange
                let fw = currentSnapshot.firmwareVersion ?? "读取中"
                let sn = currentSnapshot.serialNumber ?? "读取中"
                hardwareInfoLabel.stringValue = "固件: \(fw)  |  SN: \(sn) (按任意键唤醒)"
            } else if currentSnapshot.isStandby {
                statusLabel.stringValue = "● 优篮子 AU05 (已连接 · 硬件待机)\(batteryText)"
                statusLabel.textColor = .systemGreen
                let fw = currentSnapshot.firmwareVersion ?? "读取中"
                let sn = currentSnapshot.serialNumber ?? "读取中"
                hardwareInfoLabel.stringValue = "固件: \(fw)  |  SN: \(sn)"
            } else {
                statusLabel.stringValue = "● 优篮子 AU05 (已连接)\(batteryText)"
                statusLabel.textColor = .systemGreen
                let fw = currentSnapshot.firmwareVersion ?? "读取中"
                let sn = currentSnapshot.serialNumber ?? "读取中"
                hardwareInfoLabel.stringValue = "固件: \(fw)  |  SN: \(sn)"
            }
        } else {
            statusLabel.stringValue = "○ 设备未连接 (Offline)"
            statusLabel.textColor = .systemGray
            hardwareInfoLabel.stringValue = "请插入 2.4G 接收器或通过 USB 连接"
        }

        // Permission rows are refreshed separately; the header gives an aggregate status.
        let reports = permissionCenter.check()
        applyPermissionReports(reports, notifyObserver: false)

        // 1. Update mapping popup selections & checkmark states
        for (control, popup) in popupButtons {
            let action = config.action(for: control)
            let matchingPreset = PresetAction.allCases.first(where: { $0.actionConfig == action })
            for item in popup.itemArray {
                if let preset = item.representedObject as? PresetAction {
                    item.state = (matchingPreset == preset) ? .on : .off
                }
            }
            let customItem = popup.itemArray.first {
                $0.identifier?.rawValue == "vibekey.custom.\(control.rawValue)"
            }
            if let matchingPreset,
               let matchingItem = popup.itemArray.first(where: { ($0.representedObject as? PresetAction) == matchingPreset }) {
                customItem?.state = .off
                popup.select(matchingItem)
            } else {
                customItem?.title = "自定义: \(ActionConfigTextCodec.encode(action))"
                customItem?.state = .on
                popup.select(customItem)
            }
        }

        // 2. Update NR popup
        for item in nrPopup.itemArray {
            item.state = (UInt8(item.tag) == config.micNoiseReduction) ? .on : .off
        }
        if let nrItem = nrPopup.itemArray.first(where: { UInt8($0.tag) == config.micNoiseReduction }) {
            nrPopup.select(nrItem)
        }

        // 3. Update Mic Enable popup
        let micTag = config.micEnabled ? 1 : 0
        for item in micEnablePopup.itemArray {
            item.state = (item.tag == micTag) ? .on : .off
        }
        if let micItem = micEnablePopup.itemArray.first(where: { $0.tag == micTag }) {
            micEnablePopup.select(micItem)
        }

        // 4. Update LED popup
        for item in ledPopup.itemArray {
            if let m = item.representedObject as? LEDMode {
                item.state = (m == config.ledMode) ? .on : .off
            }
        }
        if let ledItem = ledPopup.itemArray.first(where: { ($0.representedObject as? LEDMode) == config.ledMode }) {
            ledPopup.select(ledItem)
        }

        // 5. Update Standby popup
        for item in standbyPopup.itemArray {
            item.state = (UInt32(item.tag) == config.standbySeconds) ? .on : .off
        }
        if let standbyItem = standbyPopup.itemArray.first(where: { UInt32($0.tag) == config.standbySeconds }) {
            standbyPopup.select(standbyItem)
        }

        // 6. Update connection mode
        longConnectCheckbox.state = config.longConnectedMode ? .on : .off

        // 7. Update Sleep popup
        for item in sleepPopup.itemArray {
            item.state = (UInt32(item.tag) == config.sleepSeconds) ? .on : .off
        }
        if let sleepItem = sleepPopup.itemArray.first(where: { UInt32($0.tag) == config.sleepSeconds }) {
            sleepPopup.select(sleepItem)
        }
    }

    @objc private func handleCustomMappingClicked(_ sender: NSButton) {
        guard let rawID = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawID) else { return }
        let alert = NSAlert()
        alert.messageText = "自定义 \(control.displayName)"
        alert.informativeText = "支持 ⌘ Backspace、Ctrl Alt Delete、F12、WheelUp/Down，或以 $ 开头的 Shell 命令。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "⌘ Shift T 或 $ open -a Terminal"
        input.stringValue = ActionConfigTextCodec.encode(config.action(for: control))
        alert.accessoryView = input
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            config.setAction(try ActionConfigTextCodec.parse(input.stringValue), for: control)
            onConfigurationChanged?(config)
            updateUI()
        } catch {
            let failure = NSAlert()
            failure.messageText = "动作格式无效"
            failure.informativeText = "请使用一个目标键加可选修饰键，或以 $ 开头的 Shell 命令。"
            failure.runModal()
        }
    }

    @objc private func handleMappingSelectionChanged(_ sender: NSPopUpButton) {
        guard let rawId = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawId) else { return }
        guard let preset = sender.selectedItem?.representedObject as? PresetAction else {
            // Selecting the display-only custom item must not replace the saved action.
            updateUI()
            return
        }

        config.setAction(preset.actionConfig, for: control)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleNRChanged(_ sender: NSPopUpButton) {
        let lvl = UInt8(sender.selectedItem?.tag ?? 0)
        config.micNoiseReduction = lvl
        VibeKeyHIDManager.shared.setNoiseReduction(level: lvl)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleMicEnableChanged(_ sender: NSPopUpButton) {
        let enabled = (sender.selectedItem?.tag ?? 1) == 1
        config.micEnabled = enabled
        VibeKeyHIDManager.shared.setMicrophoneEnabled(enabled)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleLEDChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.representedObject as? LEDMode else { return }
        config.ledMode = mode
        VibeKeyHIDManager.shared.setLEDMode(mode)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleStandbyChanged(_ sender: NSPopUpButton) {
        let sec = UInt32(sender.selectedItem?.tag ?? 300)
        config.standbySeconds = sec
        VibeKeyHIDManager.shared.setStandbyTimeout(seconds: sec)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleLongConnectChanged(_ sender: NSButton) {
        config.longConnectedMode = sender.state == .on
        VibeKeyHIDManager.shared.setLongConnectedMode(config.longConnectedMode)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleSleepChanged(_ sender: NSPopUpButton) {
        let sec = UInt32(sender.selectedItem?.tag ?? 3600)
        config.sleepSeconds = sec
        VibeKeyHIDManager.shared.setSleepTimeout(seconds: sec)
        onConfigurationChanged?(config)
        updateUI()
    }

    @objc private func handleCheckAllPermissionsClicked() {
        startPermissionFlow()
    }

    @objc private func handlePermissionActionClicked(_ sender: NSButton) {
        guard let permission = permissionButtons.first(where: { $0.value == sender })?.key else { return }

        if permissionCenter.statusProvider(permission) == .granted {
            permissionCenter.openSettings(for: permission)
        } else {
            _ = permissionCenter.requestAndOpenSettings(permission)
        }
        applyPermissionReports(permissionCenter.check(), notifyObserver: true)
        schedulePermissionRefresh()
    }

    func startPermissionFlow() {
        let reports = permissionCenter.check()
        guard let firstMissing = reports.first(where: \.needsAttention)?.permission else {
            permissionFlowStage = nil
            applyPermissionReports(reports, notifyObserver: true)
            return
        }

        permissionFlowStage = firstMissing
        _ = permissionCenter.requestAndOpenSettings(firstMissing)
        applyPermissionReports(permissionCenter.check(), notifyObserver: true)
        schedulePermissionRefresh()
    }

    func refreshPermissions() {
        advancePermissionFlowIfNeeded()
        applyPermissionReports(permissionCenter.check(), notifyObserver: true)
        if permissionFlowStage != nil {
            schedulePermissionRefresh()
        }
    }

    private func applyPermissionReports(_ reports: [VibeKeyPermissionReport], notifyObserver: Bool) {
        for report in reports {
            guard let label = permissionStatusLabels[report.permission],
                  let button = permissionButtons[report.permission] else { continue }

            label.stringValue = "● \(report.statusTitle)"
            label.textColor = report.status == .granted ? .systemGreen : .systemOrange
            button.title = report.status == .granted ? "打开设置…" : "检测并授权…"
            button.toolTip = report.status == .granted
                ? "打开\(report.permission.displayName)设置面板"
                : "\(report.permission.usageDescription)；点击后打开\(report.permission.displayName)设置面板"
        }

        let missing = reports.filter(\.needsAttention)
        guard Set(reports.map(\.permission)) == Set(VibeKeyPermission.allCases) else { return }

        permissionLabel.stringValue = missing.isEmpty
            ? "● 系统权限：全部已授权"
            : "○ 系统权限：\(missing.map(\.permission.displayName).joined(separator: "、"))待授权"
        permissionLabel.textColor = missing.isEmpty ? .systemGreen : .systemOrange

        if notifyObserver {
            onPermissionsUpdated?(reports)
        }
    }

    private func schedulePermissionRefresh() {
        permissionRefreshTimers.forEach { $0.invalidate() }
        permissionRefreshTimers.removeAll()

        // TCC does not provide a callback; brief polling picks up approval
        // without keeping the popover closed or restarting the app.
        for delay in [0.5, 1.5, 3.0, 6.0, 12.0, 24.0, 48.0] {
            permissionRefreshTimers.append(Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.advancePermissionFlowIfNeeded()
                let reports = self.permissionCenter.check()
                self.applyPermissionReports(reports, notifyObserver: true)
                if self.permissionFlowStage != nil {
                    self.schedulePermissionRefresh()
                }
            })
        }
    }

    private func advancePermissionFlowIfNeeded() {
        guard let stage = permissionFlowStage else { return }
        guard permissionCenter.statusProvider(stage) == .granted else { return }

        let nextMissing = VibeKeyPermission.allCases.first { permission in
            permission != stage && permissionCenter.statusProvider(permission) != .granted
        }

        if let nextMissing {
            permissionFlowStage = nextMissing
            _ = permissionCenter.requestAndOpenSettings(nextMissing)
        } else {
            permissionFlowStage = nil
        }
    }

    @objc private func handleResetKeysClicked() {
        onResetKeysRequested?()
    }

    @objc private func handleResetHwClicked() {
        onResetHardwareRequested?()
    }

    @objc private func handleRebootClicked() {
        onRebootRequested?()
    }

    @objc private func handleRefreshClicked() {
        onRefreshRequested?()
    }

    @objc private func handleCheckUpdateClicked() {
        onCheckUpdatesRequested?()
    }

    @objc private func handleQuitClicked() {
        onQuitRequested?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsVC: SettingsViewController?
    private var flashTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isHIDRecoveryWaiting = false

    private var config = VibeKeyConfiguration()
    private var currentSnapshot = VibeKeyDeviceInfoSnapshot()

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        loadConfiguration()
        VibeKeyHIDManager.shared.eventLogger = VibeKeyFileLogger()
        VibeKeyHIDManager.shared.eventLogger?.log(
            "app.launched",
            fields: [
                "accessibility": ActionPerformer.hasAccessibilityPermission() ? "granted" : "denied",
                "inputMonitoring": VibeKeyHIDManager.hasInputMonitoringAccess() ? "granted" : "denied",
                "longConnectedMode": String(config.longConnectedMode)
            ]
        )
        setupStatusItem()
        setupPopover()
        setupHIDListeners()
        setupWorkspaceObservers()
        startHIDWhenAuthorized()
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        VibeKeyHIDManager.shared.stop()
    }

    @objc private func runPermissionCheckFromMenu() {
        settingsVC?.startPermissionFlow()
    }

    private func startHIDWhenAuthorized(permissionAttempt: Int = 0, openRetryAttempt: Int = 0) {
        // Permission polling can call this repeatedly; keep one shared recovery
        // chain so open-failure retries cannot run in parallel.
        guard !isHIDRecoveryWaiting else { return }
        isHIDRecoveryWaiting = true

        if VibeKeyHIDManager.hasInputMonitoringAccess() {
            VibeKeyHIDManager.shared.start()
            // TCC can report granted while the first device open is still denied
            // after a replaced bundle. Limit retries so a persistent IOReturn
            // cannot make the menu bar process rebuild HIDManager forever.
            if !VibeKeyHIDManager.shared.isStarted, openRetryAttempt < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.isHIDRecoveryWaiting = false
                    self?.startHIDWhenAuthorized(
                        permissionAttempt: permissionAttempt,
                        openRetryAttempt: openRetryAttempt + 1
                    )
                }
            } else {
                isHIDRecoveryWaiting = false
            }
            return
        }

        if permissionAttempt == 0 {
            VibeKeyHIDManager.requestInputMonitoringAccess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isHIDRecoveryWaiting = false
            self?.startHIDWhenAuthorized(permissionAttempt: permissionAttempt + 1)
        }
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            VibeKeyHIDManager.shared.hostWillSleep()
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            VibeKeyHIDManager.shared.hostWillSleep()
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            VibeKeyHIDManager.shared.hostDidWake()
        })
    }

    private func loadConfiguration() {
        let fileConfiguration = try? VibeKeyConfigurationFile.load()
        let defaults = UserDefaults.standard
        if let saved = fileConfiguration,
           let data = try? JSONEncoder().encode(saved),
           let legacy = try? JSONDecoder().decode(VibeKeyConfiguration.self, from: data) {
            config = legacy
        } else if let data = defaults.data(forKey: "VibeKeyElementsConfig"),
                  let saved = try? JSONDecoder().decode(VibeKeyConfiguration.self, from: data) {
            config = saved
        }
        VibeKeyHIDManager.shared.standbyTimeoutSeconds = TimeInterval(config.standbySeconds)
        VibeKeyHIDManager.shared.setLongConnectedMode(config.longConnectedMode)
    }

    private func saveConfiguration() {
        try? VibeKeyConfigurationFile.save(config)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "VibeKeyElementsConfig")
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
        pop.contentSize = NSSize(width: 440, height: 736)

        let vc = SettingsViewController(config: config, snapshot: currentSnapshot)
        vc.onConfigurationChanged = { [weak self] newConfig in
            guard let self = self else { return }
            self.config = newConfig
            self.saveConfiguration()
        }
        vc.onRefreshRequested = {
            VibeKeyHIDManager.shared.refreshDeviceInfo()
        }
        vc.onResetKeysRequested = { [weak self] in
            guard let self = self else { return }
            self.config = VibeKeyConfiguration(
                topButton: .keySequence(keys: ["fn"]),
                middleButton: .keySequence(keys: ["return"]),
                bottomButton: .keySequence(keys: ["command", "delete"]),
                knobLeft: .mouseWheel(direction: .down),
                knobRight: .mouseWheel(direction: .up),
                knobPress: .keySequence(keys: ["option", "command", "a"]),
                micNoiseReduction: self.config.micNoiseReduction,
                micEnabled: self.config.micEnabled,
                ledMode: self.config.ledMode,
                standbySeconds: self.config.standbySeconds,
                sleepSeconds: self.config.sleepSeconds,
                longConnectedMode: self.config.longConnectedMode
            )
            self.saveConfiguration()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }
        vc.onResetHardwareRequested = { [weak self] in
            guard let self = self else { return }
            self.config.micNoiseReduction = 0
            self.config.micEnabled = true
            self.config.ledMode = .auto
            self.config.standbySeconds = 300
            self.config.sleepSeconds = 3600
            self.saveConfiguration()
            VibeKeyHIDManager.shared.resetHardwareDefaults()
            self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
        }
        vc.onRebootRequested = {
            VibeKeyHIDManager.shared.rebootDevice()
        }
        vc.onPermissionsUpdated = { [weak self] reports in
            guard let self else { return }
            let fields = Dictionary(uniqueKeysWithValues: reports.map {
                ($0.permission.rawValue, $0.status.rawValue)
            })
            VibeKeyHIDManager.shared.eventLogger?.log("permissions.updated", fields: fields)
            if reports.allSatisfy({ $0.status == .granted }) {
                self.startHIDWhenAuthorized()
            }
        }
        vc.onCheckUpdatesRequested = { [weak self] in
            guard let self = self else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.updaterController?.checkForUpdates(nil)
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
            if !VibeKeyHIDManager.shared.isPowerSaving {
                VibeKeyHIDManager.shared.refreshDeviceInfo()
            }
            settingsVC?.updateState(config: config, snapshot: currentSnapshot)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()

        // 1. Device Info Header
        let statusTitle: String
        if !currentSnapshot.isConnected {
            statusTitle = "优篮子 AU05 (离线)"
        } else if currentSnapshot.isDeviceOn == false {
            statusTitle = "优篮子 AU05 (已连接 · 设备关机)"
        } else {
            statusTitle = "优篮子 AU05 (已连接)"
        }
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

        // 2. Open Settings Window & Sparkle Updates
        menu.addItem(NSMenuItem(title: "打开控制面板…", action: #selector(handleOpenPopover), keyEquivalent: ","))
        let permissionItem = NSMenuItem(title: "授权检测…", action: #selector(runPermissionCheckFromMenu), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        let updateMenuItem = NSMenuItem(title: "检查更新…", action: #selector(handleCheckForUpdates), keyEquivalent: "")
        updateMenuItem.target = self
        menu.addItem(updateMenuItem)

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
            item.state = (config.micNoiseReduction == UInt8(level)) ? .on : .off
            nrMenu.addItem(item)
        }
        let nrParent = NSMenuItem(title: "麦克风降噪", action: nil, keyEquivalent: "")
        nrParent.submenu = nrMenu
        menu.addItem(nrParent)

        // 5. Mic Enable
        let micMenu = NSMenu()
        let micOnItem = NSMenuItem(title: "开启收音 (默认)", action: #selector(handleSetMicEnableMenu(_:)), keyEquivalent: "")
        micOnItem.tag = 1
        micOnItem.state = config.micEnabled ? .on : .off
        micMenu.addItem(micOnItem)

        let micOffItem = NSMenuItem(title: "静音关闭", action: #selector(handleSetMicEnableMenu(_:)), keyEquivalent: "")
        micOffItem.tag = 0
        micOffItem.state = !config.micEnabled ? .on : .off
        micMenu.addItem(micOffItem)

        let micParent = NSMenuItem(title: "麦克风开关", action: nil, keyEquivalent: "")
        micParent.submenu = micMenu
        menu.addItem(micParent)

        // 6. LED Illumination
        let ledMenu = NSMenu()
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(handleSetLED(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.state = (config.ledMode == mode) ? .on : .off
            ledMenu.addItem(item)
        }
        let ledParent = NSMenuItem(title: "指示灯模式", action: nil, keyEquivalent: "")
        ledParent.submenu = ledMenu
        menu.addItem(ledParent)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "出厂硬件复位", action: #selector(handleResetHardwareFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "恢复默认按键", action: #selector(handleResetKeysFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重启设备", action: #selector(handleRebootFromMenu), keyEquivalent: ""))

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
        config.micNoiseReduction = level
        saveConfiguration()
        VibeKeyHIDManager.shared.setNoiseReduction(level: level)
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    @objc private func handleSetMicEnableMenu(_ sender: NSMenuItem) {
        let enabled = (sender.tag == 1)
        config.micEnabled = enabled
        saveConfiguration()
        VibeKeyHIDManager.shared.setMicrophoneEnabled(enabled)
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    @objc private func handleSetLED(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? LEDMode else { return }
        config.ledMode = mode
        saveConfiguration()
        VibeKeyHIDManager.shared.setLEDMode(mode)
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    @objc private func handleResetHardwareFromMenu() {
        config.micNoiseReduction = 0
        config.micEnabled = true
        config.ledMode = .auto
        config.standbySeconds = 300
        config.sleepSeconds = 3600
        saveConfiguration()
        VibeKeyHIDManager.shared.resetHardwareDefaults()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    @objc private func handleResetKeysFromMenu() {
        config = VibeKeyConfiguration(
            topButton: .keySequence(keys: ["fn"]),
            middleButton: .keySequence(keys: ["return"]),
            bottomButton: .keySequence(keys: ["command", "delete"]),
            knobLeft: .mouseWheel(direction: .down),
            knobRight: .mouseWheel(direction: .up),
            knobPress: .keySequence(keys: ["option", "command", "a"]),
            micNoiseReduction: config.micNoiseReduction,
            micEnabled: config.micEnabled,
            ledMode: config.ledMode,
            standbySeconds: config.standbySeconds,
            sleepSeconds: config.sleepSeconds,
            longConnectedMode: config.longConnectedMode
        )
        saveConfiguration()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    @objc private func handleRebootFromMenu() {
        VibeKeyHIDManager.shared.rebootDevice()
    }

    @objc private func handleCheckForUpdates() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        updaterController?.checkForUpdates(nil)
    }

    private func updateStatusItemDisplay(overrideText: String? = nil) {
        guard let button = statusItem?.button else { return }

        // 1. Native SF Symbol template icon with standard spacing
        let iconName: String
        if !currentSnapshot.isConnected {
            iconName = "dial.medium"
        } else if VibeKeyHIDManager.shared.isPowerSaving {
            iconName = "dial.medium"
        } else {
            iconName = "dial.medium.fill"
        }
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

        if currentSnapshot.isDeviceOn == false {
            let attr = NSAttributedString(
                string: " OFF",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .bold),
                    .foregroundColor: NSColor.systemGray
                ]
            )
            button.attributedTitle = attr
            button.toolTip = "优篮子 AU05 · 已连接 · 设备关机"
            return
        }

        if let battery = currentSnapshot.battery {
            let bolt = battery.isCharging ? " ⚡" : ""
            let standbyMarker = VibeKeyHIDManager.shared.isPowerSaving ? " 💤" : ""
            let text = " \(battery.percent)%\(bolt)\(standbyMarker)"
            let attr = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .medium)
                ]
            )
            button.attributedTitle = attr
            let chargeState = battery.isCharging
                ? "充电中"
                : (VibeKeyHIDManager.shared.isPowerSaving ? "闲置待机省电中" : "电池供电")
            button.toolTip = "优篮子 AU05 · 电量 \(battery.percent)% (\(chargeState), \(battery.voltageMillivolts)mV)"
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = VibeKeyHIDManager.shared.isPowerSaving ? "优篮子 AU05 (待机省电中)" : "优篮子 AU05 (已连接)"
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

        VibeKeyHIDManager.shared.onPowerSavingChanged = { [weak self] _ in
            guard let self = self else { return }
            // Snapshot standby is the hardware display state; menu chrome tracks
            // the manager's local offline-handoff state separately.
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
                VibeKeyHIDManager.shared.eventLogger?.log(
                    "action.triggered",
                    fields: ["control": control.rawValue]
                )
                ActionPerformer.perform(action)
            }
        }
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
