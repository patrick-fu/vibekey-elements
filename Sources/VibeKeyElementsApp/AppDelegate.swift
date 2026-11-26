import AppKit
import ApplicationServices
import Foundation
import Sparkle
import VibeKeyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private let processStartedAt = Date()
    private let strings = VibeKeyStrings.current
    private let permissionRecovery = PermissionRecoveryCoordinator()
    private lazy var inputDispatcher = VibeKeyInputDispatcher { [weak self] trigger in
        self?.handleInputTrigger(trigger)
    }

    private var updaterController: SPUStandardUpdaterController?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsVC: SettingsViewController?
    private var flashTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isHIDRecoveryWaiting = false
    private var isHostSuspended = false

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
                "inputMonitoring": VibeKeyPermissionCenter.live.statusProvider(.inputMonitoring).rawValue,
                "longConnectedMode": String(config.longConnectedMode)
            ]
        )
        setupStatusItem()
        setupPopover()
        setupHIDListeners()
        setupWorkspaceObservers()
        promptForAccessibilityIfMissing()
        startLaunchPermissionRecoveryIfNeeded()
        startHIDWhenAuthorized()
        permissionRecovery.updateProbeTimer()
        permissionRecovery.probeForFreshPermissionsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        inputDispatcher.cancelAll()
        ActionPerformer.releaseAllHolds(synchronous: true)
        permissionRecovery.stop()
        VibeKeyHIDManager.shared.stop()
    }

    @objc private func runPermissionCheckFromMenu() {
        settingsVC?.startPermissionFlow()
    }

    private func promptForAccessibilityIfMissing() {
        guard !ActionPerformer.hasAccessibilityPermission() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func inputMonitoringStatus() -> VibeKeyPermissionStatus {
        VibeKeyPermissionCenter.live.statusProvider(.inputMonitoring)
    }

    private func startLaunchPermissionRecoveryIfNeeded() {
        let missing = VibeKeyPermission.allCases.filter {
            VibeKeyPermissionCenter.live.statusProvider($0) != .granted
        }
        guard !missing.isEmpty else { return }

        VibeKeyHIDManager.shared.eventLogger?.log("permission.recovery.started", fields: [
            "reason": "launch",
            "missing": missing.map(\.rawValue).sorted().joined(separator: ",")
        ])
        settingsVC?.startPermissionFlow()
    }

    private func startHIDWhenAuthorized(openRetryAttempt: Int = 0) {
        let status = inputMonitoringStatus()
        VibeKeyHIDManager.shared.eventLogger?.log("hid.permission.preflight", fields: [
            "attempt": String(openRetryAttempt),
            "status": status.rawValue
        ])

        // TCC may hard-deny ListenEvent on first launch without presenting a
        // prompt. The permission flow owns denied/undetermined recovery: it
        // opens the exact pane and keeps polling until the state changes.
        guard status == .granted else {
            VibeKeyHIDManager.shared.eventLogger?.log("hid.permission.\(status.rawValue)", fields: [
                "status": status.rawValue,
                "recoveryOwner": "permissionCenter"
            ])
            return
        }

        // Permission polling can call this repeatedly; keep one shared recovery
        // chain so open-failure retries cannot run in parallel.
        guard !isHIDRecoveryWaiting else { return }
        isHIDRecoveryWaiting = true
        VibeKeyHIDManager.shared.start()

        // TCC can report granted while the first device open is still denied
        // after a replaced bundle. Limit retries so a persistent IOReturn
        // cannot make the menu bar process rebuild HIDManager forever.
        if !VibeKeyHIDManager.shared.isStarted, openRetryAttempt < 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.isHIDRecoveryWaiting = false
                self?.startHIDWhenAuthorized(openRetryAttempt: openRetryAttempt + 1)
            }
        } else {
            isHIDRecoveryWaiting = false
        }
    }

    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated(work)
            }
        }
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.onMain {
                self?.isHostSuspended = true
                self?.inputDispatcher.cancelAll()
                ActionPerformer.releaseAllHolds()
                VibeKeyHIDManager.shared.hostWillSleep()
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.onMain {
                self?.isHostSuspended = true
                self?.inputDispatcher.cancelAll()
                ActionPerformer.releaseAllHolds()
                VibeKeyHIDManager.shared.hostWillSleep()
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.onMain {
                self?.logDisplayLifecycle("display.sleep")
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.onMain {
                self?.logDisplayLifecycle("display.wake")
            }
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Self.onMain {
                self?.isHostSuspended = false
                VibeKeyHIDManager.shared.hostDidWake()
            }
        })
    }

    private func logDisplayLifecycle(_ event: String) {
        let snapshot = currentSnapshot
        VibeKeyHIDManager.shared.eventLogger?.log(event, fields: [
            "battery": snapshot.battery.map { "\($0.percent)%\($0.isCharging ? "+charging" : "")" } ?? "unknown",
            "connected": String(snapshot.isConnected),
            "deviceOn": snapshot.isDeviceOn.map(String.init) ?? "unknown",
            "hidPowerSaving": String(VibeKeyHIDManager.shared.isPowerSaving),
            "processUptimeSeconds": String(
                Int(Date().timeIntervalSince(processStartedAt))
            )
        ])
    }

    private func loadConfiguration() {
        if let saved = try? VibeKeyConfigurationFile.load() {
            config = saved
        } else if let data = UserDefaults.standard.data(forKey: "VibeKeyElementsConfig"),
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

    private func resetKeyMappings() {
        config = config.resettingKeyMappingsToDefaults()
        saveConfiguration()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    private func resetHardwareDefaults() {
        config = config.resettingHardwareSettingsToDefaults()
        saveConfiguration()
        VibeKeyHIDManager.shared.resetHardwareDefaults()
        settingsVC?.updateState(config: config, snapshot: currentSnapshot)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item
        // NSStatusItem is not yet through its initial layout pass; synchronous
        // title/image mutation here triggers AppKit layout recursion warnings.
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusItemDisplay()
        }
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true

        let vc = SettingsViewController(config: config, snapshot: currentSnapshot, strings: strings)
        vc.onConfigurationChanged = { [weak self] newConfig in
            guard let self = self else { return }
            self.config = newConfig
            self.saveConfiguration()
        }
        vc.onRefreshRequested = {
            VibeKeyHIDManager.shared.refreshDeviceInfo()
        }
        vc.onResetKeysRequested = { [weak self] in
            self?.resetKeyMappings()
        }
        vc.onResetHardwareRequested = { [weak self] in
            self?.resetHardwareDefaults()
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
            self.permissionRecovery.updateProbeTimer()
        }
        vc.onCheckUpdatesRequested = { [weak self] in
            self?.handleCheckForUpdates()
        }
        vc.onQuitRequested = {
            NSApplication.shared.terminate(nil)
        }

        pop.contentViewController = vc
        self.popover = pop
        self.settingsVC = vc

        // Setting popover size immediately after installing a newly loaded
        // content view can force layout during AppKit's initial layout pass.
        DispatchQueue.main.async { [weak self] in
            guard let popover = self?.popover else { return }
            _ = vc.view
            popover.contentSize = vc.preferredContentSize
        }
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
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        guard let popover, let settingsVC else { return }
        _ = settingsVC.view
        popover.contentSize = settingsVC.preferredContentSize
        settingsVC.updateState(config: config, snapshot: currentSnapshot)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let presentation = VibeKeyDevicePresentation(
            snapshot: currentSnapshot,
            isLocalPowerSaving: VibeKeyHIDManager.shared.isPowerSaving,
            strings: strings
        )

        // 1. Device Info Header
        let headerItem = NSMenuItem(title: presentation.menuStatusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if let fwTitle = presentation.menuFirmwareTitle {
            let fwItem = NSMenuItem(title: fwTitle, action: nil, keyEquivalent: "")
            fwItem.isEnabled = false
            menu.addItem(fwItem)
        }
        if let snTitle = presentation.menuSerialTitle {
            let snItem = NSMenuItem(title: snTitle, action: nil, keyEquivalent: "")
            snItem.isEnabled = false
            menu.addItem(snItem)
        }
        if let batteryTitle = presentation.menuBatteryTitle {
            let batteryItem = NSMenuItem(title: batteryTitle, action: nil, keyEquivalent: "")
            batteryItem.isEnabled = false
            menu.addItem(batteryItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Open Settings Window & Sparkle Updates
        menu.addItem(NSMenuItem(title: strings[.menuOpenPanel], action: #selector(handleOpenPopover), keyEquivalent: ","))
        let permissionItem = NSMenuItem(title: strings[.menuCheckPermissions], action: #selector(runPermissionCheckFromMenu), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        let updateMenuItem = NSMenuItem(title: strings[.buttonCheckUpdates], action: #selector(handleCheckForUpdates), keyEquivalent: "")
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
                let item = NSMenuItem(title: preset.displayName(in: strings.language), action: #selector(handleMenuSetKeyAction(_:)), keyEquivalent: "")
                item.representedObject = (control, preset)
                item.state = (preset.actionConfig == currentAction) ? .on : .off
                sub.addItem(item)
            }
            let parent = NSMenuItem(title: control.displayName(in: strings.language), action: nil, keyEquivalent: "")
            parent.submenu = sub
            keysMenu.addItem(parent)
        }
        let keysParent = NSMenuItem(title: strings[.menuKeyMapping], action: nil, keyEquivalent: "")
        keysParent.submenu = keysMenu
        menu.addItem(keysParent)

        // 4. Noise Reduction with explicit Checkmarks
        let nrMenu = NSMenu()
        for option in VibeKeyHardwareOptions.noiseReductionLevels {
            let item = NSMenuItem(title: strings[option.shortTitleKey], action: #selector(handleSetNR(_:)), keyEquivalent: "")
            item.tag = Int(option.level)
            item.state = (config.micNoiseReduction == option.level) ? .on : .off
            nrMenu.addItem(item)
        }
        let nrParent = NSMenuItem(title: strings[.menuNoiseReduction], action: nil, keyEquivalent: "")
        nrParent.submenu = nrMenu
        menu.addItem(nrParent)

        // 5. Mic Enable
        let micMenu = NSMenu()
        let micOnItem = NSMenuItem(title: strings[.micShortOnDefault], action: #selector(handleSetMicEnableMenu(_:)), keyEquivalent: "")
        micOnItem.tag = 1
        micOnItem.state = config.micEnabled ? .on : .off
        micMenu.addItem(micOnItem)

        let micOffItem = NSMenuItem(title: strings[.micShortOff], action: #selector(handleSetMicEnableMenu(_:)), keyEquivalent: "")
        micOffItem.tag = 0
        micOffItem.state = !config.micEnabled ? .on : .off
        micMenu.addItem(micOffItem)

        let micParent = NSMenuItem(title: strings[.menuMicrophone], action: nil, keyEquivalent: "")
        micParent.submenu = micMenu
        menu.addItem(micParent)

        // 6. LED Illumination
        let ledMenu = NSMenu()
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.displayName(in: strings.language), action: #selector(handleSetLED(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.state = (config.ledMode == mode) ? .on : .off
            ledMenu.addItem(item)
        }
        let ledParent = NSMenuItem(title: strings[.menuLEDMode], action: nil, keyEquivalent: "")
        ledParent.submenu = ledMenu
        menu.addItem(ledParent)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: strings[.buttonFactoryReset], action: #selector(handleResetHardwareFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: strings[.buttonResetKeys], action: #selector(handleResetKeysFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: strings[.buttonReboot], action: #selector(handleRebootFromMenu), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: strings[.menuQuitApp], action: #selector(handleQuit), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func handleOpenPopover() {
        guard let button = statusItem?.button else { return }
        VibeKeyHIDManager.shared.refreshDeviceInfo()
        showPopover(relativeTo: button)
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
        resetHardwareDefaults()
    }

    @objc private func handleResetKeysFromMenu() {
        resetKeyMappings()
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
        let presentation = VibeKeyDevicePresentation(
            snapshot: currentSnapshot,
            isLocalPowerSaving: VibeKeyHIDManager.shared.isPowerSaving,
            strings: strings
        )

        // 1. Native SF Symbol template icon with standard spacing
        if let icon = NSImage(systemSymbolName: presentation.statusItemSymbolName, accessibilityDescription: "VibeKey") {
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeft
        }

        // 2. Clear key flash feedback
        if let override = overrideText {
            button.attributedTitle = NSAttributedString(
                string: " \(override)",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .bold),
                    .foregroundColor: NSColor.controlAccentColor
                ]
            )
            return
        }

        // 3. Clean status bar typography
        button.toolTip = presentation.statusItemToolTip
        if presentation.statusItemText.isEmpty {
            button.attributedTitle = NSAttributedString(string: "")
        } else if presentation.statusItemIsMuted {
            button.attributedTitle = NSAttributedString(
                string: presentation.statusItemText,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12.0, weight: .bold),
                    .foregroundColor: NSColor.systemGray
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(
                string: presentation.statusItemText,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .medium)
                ]
            )
        }
    }

    private func triggerKeyFlash(_ label: String) {
        flashTimer?.invalidate()
        updateStatusItemDisplay(overrideText: "[\(label)]")

        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Self.onMain {
                self?.updateStatusItemDisplay()
            }
        }
    }

    private func setupHIDListeners() {
        VibeKeyHIDManager.shared.onDeviceConnected = { [weak self] in
            Self.onMain {
                guard let self else { return }
                self.currentSnapshot.isConnected = true
                self.updateStatusItemDisplay()
                self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
            }
        }

        VibeKeyHIDManager.shared.onDeviceDisconnected = { [weak self] in
            Self.onMain {
                guard let self else { return }
                self.inputDispatcher.cancelAll()
                ActionPerformer.releaseAllHolds()
                self.currentSnapshot = VibeKeyDeviceInfoSnapshot(isConnected: false)
                self.updateStatusItemDisplay()
                self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
            }
        }

        VibeKeyHIDManager.shared.onPowerSavingChanged = { [weak self] _ in
            Self.onMain {
                guard let self else { return }
                // Snapshot standby is the hardware display state; menu chrome tracks
                // the manager's local offline-handoff state separately.
                self.updateStatusItemDisplay()
                self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
            }
        }

        VibeKeyHIDManager.shared.onDeviceInfoUpdated = { [weak self] snapshot in
            Self.onMain {
                guard let self else { return }
                if snapshot.isDeviceOn == false {
                    self.inputDispatcher.cancelAll()
                    ActionPerformer.releaseAllHolds()
                }
                self.currentSnapshot = snapshot
                self.updateStatusItemDisplay()
                self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
            }
        }

        VibeKeyHIDManager.shared.onBatteryUpdated = { [weak self] battery in
            Self.onMain {
                guard let self else { return }
                self.currentSnapshot.battery = battery
                self.updateStatusItemDisplay()
                self.settingsVC?.updateState(config: self.config, snapshot: self.currentSnapshot)
            }
        }

        VibeKeyHIDManager.shared.onEventReceived = { [weak self] control, phase in
            Self.onMain {
                guard let self else { return }
                guard !self.isHostSuspended, self.currentSnapshot.isConnected else { return }
                self.inputDispatcher.handle(control: control, phase: phase, configuration: self.config)
            }
        }
    }

    private func handleInputTrigger(_ trigger: VibeKeyInputTrigger) {
        switch trigger {
        case let .shortPress(control, action):
            triggerKeyFlash(control.displayLabel)
            VibeKeyHIDManager.shared.eventLogger?.log(
                "action.triggered",
                fields: ["control": control.rawValue, "longPress": "false"]
            )
            ActionPerformer.perform(action)

        case let .longPressTap(control, action):
            triggerKeyFlash(strings.longPressFlashLabel(control.displayLabel))
            VibeKeyHIDManager.shared.eventLogger?.log(
                "action.triggered",
                fields: ["control": control.rawValue, "longPress": "true"]
            )
            ActionPerformer.perform(action)

        case let .longPressHoldBegin(control, action):
            triggerKeyFlash(strings.longPressFlashLabel(control.displayLabel))
            VibeKeyHIDManager.shared.eventLogger?.log(
                "action.triggered",
                fields: ["control": control.rawValue, "longPress": "true", "hold": "true"]
            )
            ActionPerformer.beginHold(action)

        case let .longPressHoldEnd(_, action):
            ActionPerformer.endHold(action)
        }
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        Self.onMain {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
