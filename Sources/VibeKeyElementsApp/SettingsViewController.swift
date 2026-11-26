import AppKit
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

    private let strings: VibeKeyStrings
    private var config: VibeKeyConfiguration
    private var currentSnapshot: VibeKeyDeviceInfoSnapshot

    private let titleLabel = NSTextField(labelWithString: "VibeKey Elements")
    private let subtitleLabel: NSTextField
    private let statusLabel: NSTextField
    private let hardwareInfoLabel = NSTextField(labelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "")

    private var popupButtons: [InputControl: NSPopUpButton] = [:]
    private var customButtons: [InputControl: NSButton] = [:]
    private var longPopupButtons: [InputControl: NSPopUpButton] = [:]
    private var longCustomButtons: [InputControl: NSButton] = [:]
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
    private let longConnectCheckbox: NSButton

    init(
        config: VibeKeyConfiguration,
        snapshot: VibeKeyDeviceInfoSnapshot,
        strings: VibeKeyStrings = .current,
        permissionCenter: VibeKeyPermissionCenter = VibeKeyPermissionCenter(
            statusProvider: { VibeKeyPermissionCenter.live.statusProvider($0) },
            requestHandler: { VibeKeyPermissionCenter.live.requestHandler($0) },
            settingsOpener: { NSWorkspace.shared.open($0) }
        )
    ) {
        self.strings = strings
        self.config = config
        self.currentSnapshot = snapshot
        self.permissionCenter = permissionCenter
        self.subtitleLabel = NSTextField(labelWithString: strings[.panelSubtitle])
        self.statusLabel = NSTextField(labelWithString: strings[.panelDetecting])
        self.longConnectCheckbox = NSButton(checkboxWithTitle: strings[.longConnectMode], target: nil, action: nil)
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
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        hardwareInfoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hardwareInfoLabel.textColor = .secondaryLabelColor
        hardwareInfoLabel.maximumNumberOfLines = 2
        hardwareInfoLabel.lineBreakMode = .byWordWrapping
        hardwareInfoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        permissionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        permissionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [titleLabel, subtitleLabel, statusLabel, hardwareInfoLabel, permissionLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 3

        // 2. System Permission Section
        let permissionHeading = makeSectionHeader(strings[.sectionPermissions])
        let checkPermissionButton = NSButton(
            title: strings[.buttonCheckAllPermissions],
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
        let mappingHeading = makeSectionHeader(strings[.sectionMapping])
        let mappingGrid = makeMappingGrid()

        // 4. Hardware Settings Section
        let hardwareHeading = makeSectionHeader(strings[.sectionHardware])
        let hardwareGrid = makeHardwareGrid()

        // 5. Hardware Maintenance Section
        let maintenanceHeading = makeSectionHeader(strings[.sectionMaintenance])
        let resetKeysBtn = NSButton(title: strings[.buttonResetKeys], target: self, action: #selector(handleResetKeysClicked))
        resetKeysBtn.bezelStyle = .rounded
        resetKeysBtn.font = .systemFont(ofSize: 11)

        let resetHwBtn = NSButton(title: strings[.buttonFactoryReset], target: self, action: #selector(handleResetHwClicked))
        resetHwBtn.bezelStyle = .rounded
        resetHwBtn.font = .systemFont(ofSize: 11)

        let rebootBtn = NSButton(title: strings[.buttonReboot], target: self, action: #selector(handleRebootClicked))
        rebootBtn.bezelStyle = .rounded
        rebootBtn.font = .systemFont(ofSize: 11)

        let maintenanceStack = NSStackView(views: [resetKeysBtn, resetHwBtn, rebootBtn])
        maintenanceStack.orientation = .horizontal
        maintenanceStack.alignment = .centerY
        maintenanceStack.spacing = 8

        // 6. Action Buttons
        let refreshBtn = NSButton(title: strings[.buttonRefresh], target: self, action: #selector(handleRefreshClicked))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = .systemFont(ofSize: 11)

        let checkUpdateBtn = NSButton(title: strings[.buttonCheckUpdates], target: self, action: #selector(handleCheckUpdateClicked))
        checkUpdateBtn.bezelStyle = .rounded
        checkUpdateBtn.font = .systemFont(ofSize: 11)

        let quitBtn = NSButton(title: strings[.quit], target: self, action: #selector(handleQuitClicked))
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

        // Fit popover width to localized controls (e.g. longer French labels/buttons)
        // while preserving the 440x736 baseline for compact locales.
        let requiredControlWidth = [
            permissionHeadingStack.fittingSize.width,
            permissionGrid.fittingSize.width,
            mappingGrid.fittingSize.width,
            hardwareGrid.fittingSize.width,
            maintenanceStack.fittingSize.width,
            bottomStack.fittingSize.width
        ].max() ?? 0
        let contentWidth = max(440, ceil(requiredControlWidth) + 36)
        statusLabel.preferredMaxLayoutWidth = contentWidth - 36
        hardwareInfoLabel.preferredMaxLayoutWidth = contentWidth - 36
        let contentHeight = max(736, ceil(mainStack.fittingSize.height) + 28)
        let preferred = NSSize(width: contentWidth, height: contentHeight)
        root.frame = NSRect(origin: .zero, size: preferred)
        self.preferredContentSize = preferred

        self.view = root

        // AppKit may already be inside the first layout pass when loadView
        // returns. Mutating stack views here triggers layoutSubtreeIfNeeded
        // recursion; defer the first model-to-UI refresh to a clean pass.
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
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
            let nameLabel = NSTextField(labelWithString: permission.displayName(in: strings.language))
            nameLabel.font = .systemFont(ofSize: 12, weight: .medium)

            let statusLabel = NSTextField(labelWithString: strings[.permissionChecking])
            statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
            statusLabel.toolTip = permission.usageDescription(in: strings.language)

            let actionButton = NSButton(
                title: strings[.permissionCheckAndGrant],
                target: self,
                action: #selector(handlePermissionActionClicked(_:))
            )
            actionButton.bezelStyle = .rounded
            actionButton.font = .systemFont(ofSize: 11)
            permissionButtons[permission] = actionButton
            actionButton.toolTip = permission.usageDescription(in: strings.language)
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
            .topButton, .middleButton, .bottomButton,
            .knobLeft, .knobRight, .knobPress
        ]

        func makeColumnHeader(_ title: String) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }

        func makeMappingCell(control: InputControl, isLongPress: Bool) -> NSStackView {
            let idPrefix = isLongPress ? "vibekey.long." : ""
            let customPrefix = isLongPress ? "vibekey.long.custom." : "vibekey.custom."

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = .systemFont(ofSize: 12)
            popup.identifier = NSUserInterfaceItemIdentifier("\(idPrefix)\(control.rawValue)")
            popup.target = self
            popup.action = #selector(handleMappingSelectionChanged(_:))

            if isLongPress {
                let noneItem = NSMenuItem(title: strings[.mappingLongPressNone], action: nil, keyEquivalent: "")
                noneItem.representedObject = "none"
                popup.menu?.addItem(noneItem)
            }

            for preset in PresetAction.allCases {
                let item = NSMenuItem(title: preset.displayName(in: strings.language), action: nil, keyEquivalent: "")
                item.representedObject = preset
                popup.menu?.addItem(item)
            }

            let customItem = NSMenuItem(title: strings[.mappingCustomItem], action: nil, keyEquivalent: "")
            customItem.representedObject = "custom"
            customItem.identifier = NSUserInterfaceItemIdentifier("\(customPrefix)\(control.rawValue)")
            popup.menu?.addItem(customItem)

            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
            popup.heightAnchor.constraint(equalToConstant: 24).isActive = true

            let customButton = NSButton(
                title: "…",
                target: self,
                action: #selector(handleCustomMappingClicked(_:))
            )
            customButton.bezelStyle = .rounded
            customButton.font = .systemFont(ofSize: 11, weight: .medium)
            let customTitle = strings.customTitle(control.displayName(in: strings.language), isLongPress: isLongPress)
            customButton.identifier = NSUserInterfaceItemIdentifier("\(idPrefix)\(control.rawValue)")
            customButton.toolTip = customTitle
            customButton.setAccessibilityLabel(customTitle)
            customButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
            customButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

            if isLongPress {
                longPopupButtons[control] = popup
                longCustomButtons[control] = customButton
            } else {
                popupButtons[control] = popup
                customButtons[control] = customButton
            }

            let stack = NSStackView(views: [popup, customButton])
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            return stack
        }

        var rows: [[NSView]] = [[
            makeColumnHeader(strings[.mappingHeaderControl]),
            makeColumnHeader(strings[.mappingHeaderShortPress]),
            makeColumnHeader(strings[.mappingHeaderLongPress])
        ]]

        for control in controls {
            let label = NSTextField(labelWithString: control.displayName(in: strings.language))
            label.font = .systemFont(ofSize: 12, weight: .medium)

            let shortCell = makeMappingCell(control: control, isLongPress: false)
            let longCell: NSView = control.supportsLongPress
                ? makeMappingCell(control: control, isLongPress: true)
                : NSTextField(labelWithString: "")
            rows.append([label, shortCell, longCell])
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 5
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        grid.column(at: 2).xPlacement = .fill
        return grid
    }

    private func makeHardwareGrid() -> NSGridView {
        // 1. Noise reduction
        let nrLabel = NSTextField(labelWithString: strings[.hwNoiseReduction])
        nrLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nrPopup.font = .systemFont(ofSize: 12)
        nrPopup.target = self
        nrPopup.action = #selector(handleNRChanged(_:))
        for option in VibeKeyHardwareOptions.noiseReductionLevels {
            let item = NSMenuItem(title: strings[option.fullTitleKey], action: nil, keyEquivalent: "")
            item.tag = Int(option.level)
            nrPopup.menu?.addItem(item)
        }
        nrPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        nrPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 2. Microphone Enable/Mute
        let micLabel = NSTextField(labelWithString: strings[.hwMicrophone])
        micLabel.font = .systemFont(ofSize: 12, weight: .medium)
        micEnablePopup.font = .systemFont(ofSize: 12)
        micEnablePopup.target = self
        micEnablePopup.action = #selector(handleMicEnableChanged(_:))
        let micOptions: [(String, Int)] = [
            (strings[.micShortOnDefault], 1),
            (strings[.micShortOff], 0)
        ]
        for (name, val) in micOptions {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.tag = val
            micEnablePopup.menu?.addItem(item)
        }
        micEnablePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        micEnablePopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 3. LED illumination
        let ledLabel = NSTextField(labelWithString: strings[.hwLED])
        ledLabel.font = .systemFont(ofSize: 12, weight: .medium)
        ledPopup.font = .systemFont(ofSize: 12)
        ledPopup.target = self
        ledPopup.action = #selector(handleLEDChanged(_:))
        for mode in LEDMode.allCases {
            let item = NSMenuItem(title: mode.displayName(in: strings.language), action: nil, keyEquivalent: "")
            item.representedObject = mode
            ledPopup.menu?.addItem(item)
        }
        ledPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        ledPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 4. Standby delay
        let standbyLabel = NSTextField(labelWithString: strings[.hwStandby])
        standbyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        standbyPopup.font = .systemFont(ofSize: 12)
        standbyPopup.target = self
        standbyPopup.action = #selector(handleStandbyChanged(_:))
        for option in VibeKeyHardwareOptions.standbyOptions {
            let item = NSMenuItem(title: strings[option.titleKey], action: nil, keyEquivalent: "")
            item.tag = Int(option.seconds)
            standbyPopup.menu?.addItem(item)
        }
        standbyPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        standbyPopup.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 5. Sleep delay
        let sleepLabel = NSTextField(labelWithString: strings[.hwSleep])
        sleepLabel.font = .systemFont(ofSize: 12, weight: .medium)
        sleepPopup.font = .systemFont(ofSize: 12)
        sleepPopup.target = self
        sleepPopup.action = #selector(handleSleepChanged(_:))
        for option in VibeKeyHardwareOptions.sleepOptions {
            let item = NSMenuItem(title: strings[option.titleKey], action: nil, keyEquivalent: "")
            item.tag = Int(option.seconds)
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
            [makeSectionHeader(strings[.sectionConnectionMode]), longConnectCheckbox]
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
        let presentation = VibeKeyDevicePresentation(
            snapshot: currentSnapshot,
            isLocalPowerSaving: isLocalPowerSaving,
            strings: strings
        )
        statusLabel.stringValue = presentation.panelStatusText
        switch presentation.panelStatusTone {
        case .connected: statusLabel.textColor = .systemGreen
        case .powerSaving: statusLabel.textColor = .systemOrange
        case .inactive: statusLabel.textColor = .systemGray
        }
        hardwareInfoLabel.stringValue = presentation.panelHardwareInfoText

        // Permission rows are refreshed separately; the header gives an aggregate status.
        let reports = permissionCenter.check()
        applyPermissionReports(reports, notifyObserver: false)

        // 1. Update short-press mapping popup selections & checkmark states
        for (control, popup) in popupButtons {
            updateMappingPopup(
                popup,
                action: config.action(for: control),
                customItemID: "vibekey.custom.\(control.rawValue)"
            )
        }

        // 1b. Update long-press mapping popup selections & checkmark states
        for (control, popup) in longPopupButtons {
            updateMappingPopup(
                popup,
                action: config.longPressAction(for: control),
                customItemID: "vibekey.long.custom.\(control.rawValue)"
            )
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

    private func updateMappingPopup(
        _ popup: NSPopUpButton,
        action: ActionConfig?,
        customItemID: String
    ) {
        let customItem = popup.itemArray.first { $0.identifier?.rawValue == customItemID }
        guard let action else {
            for item in popup.itemArray { item.state = .off }
            customItem?.title = strings[.mappingCustomItem]
            if let noneItem = popup.itemArray.first(where: { ($0.representedObject as? String) == "none" }) {
                noneItem.state = .on
                popup.select(noneItem)
            }
            return
        }

        let matchingPreset = PresetAction.allCases.first(where: { $0.actionConfig == action })
        for item in popup.itemArray {
            if let preset = item.representedObject as? PresetAction {
                item.state = (matchingPreset == preset) ? .on : .off
            } else {
                item.state = .off
            }
        }

        if let matchingPreset,
           let matchingItem = popup.itemArray.first(where: { ($0.representedObject as? PresetAction) == matchingPreset }) {
            customItem?.title = strings[.mappingCustomItem]
            popup.select(matchingItem)
        } else {
            customItem?.title = strings.mappingCustomCurrent(ActionConfigTextCodec.encode(action))
            customItem?.state = .on
            popup.select(customItem)
        }
    }

    private func parseMappingIdentifier(_ rawID: String?) -> (control: InputControl, isLongPress: Bool)? {
        guard let rawID else { return nil }
        let prefix = "vibekey.long."
        let isLongPress = rawID.hasPrefix(prefix)
        let controlRaw = isLongPress ? String(rawID.dropFirst(prefix.count)) : rawID
        guard let control = InputControl(rawValue: controlRaw) else { return nil }
        return (control, isLongPress)
    }

    private func openCustomMappingAlert(for control: InputControl, isLongPress: Bool) {
        let currentAction = isLongPress
            ? (config.longPressAction(for: control) ?? .keySequence(keys: []))
            : config.action(for: control)
        let encoded = ActionConfigTextCodec.encode(currentAction)

        let alert = NSAlert()
        alert.messageText = strings.customTitle(control.displayName(in: strings.language), isLongPress: isLongPress)
        alert.informativeText = strings[.customMessage]

        let recorder = ShortcutRecorderField(
            displayText: encoded,
            strings: strings,
            allowStandaloneModifier: isLongPress
        )
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = strings[.customPlaceholder]
        input.stringValue = encoded
        recorder.onRecorded = { [weak input] action in
            input?.stringValue = ActionConfigTextCodec.encode(action)
        }

        let accessory = NSStackView(views: [recorder, input])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
        alert.accessoryView = accessory
        alert.addButton(withTitle: strings[.save])
        alert.addButton(withTitle: strings[.cancel])
        if isLongPress {
            alert.addButton(withTitle: strings[.buttonClearLongPress])
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = recorder
        let response = alert.runModal()
        if isLongPress, response == .alertThirdButtonReturn {
            config.setLongPressAction(nil, for: control)
            onConfigurationChanged?(config)
            updateUI()
            return
        }
        guard response == .alertFirstButtonReturn else {
            updateUI()
            return
        }
        do {
            let parsed = try ActionConfigTextCodec.parse(input.stringValue, allowStandaloneModifier: isLongPress)
            if isLongPress {
                config.setLongPressAction(parsed, for: control)
            } else {
                config.setAction(parsed, for: control)
            }
            onConfigurationChanged?(config)
            updateUI()
        } catch {
            let failure = NSAlert()
            failure.messageText = strings[.customInvalidTitle]
            failure.informativeText = strings[.customInvalidMessage]
            failure.runModal()
            updateUI()
        }
    }

    @objc private func handleCustomMappingClicked(_ sender: NSButton) {
        guard let target = parseMappingIdentifier(sender.identifier?.rawValue) else { return }
        openCustomMappingAlert(for: target.control, isLongPress: target.isLongPress)
    }

    @objc private func handleMappingSelectionChanged(_ sender: NSPopUpButton) {
        guard let target = parseMappingIdentifier(sender.identifier?.rawValue) else { return }
        if let preset = sender.selectedItem?.representedObject as? PresetAction {
            if target.isLongPress {
                config.setLongPressAction(preset.actionConfig, for: target.control)
            } else {
                config.setAction(preset.actionConfig, for: target.control)
            }
            onConfigurationChanged?(config)
            updateUI()
            return
        }

        if target.isLongPress, (sender.selectedItem?.representedObject as? String) == "none" {
            config.setLongPressAction(nil, for: target.control)
            onConfigurationChanged?(config)
            updateUI()
            return
        }

        if (sender.selectedItem?.representedObject as? String) == "custom" {
            openCustomMappingAlert(for: target.control, isLongPress: target.isLongPress)
            return
        }

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
        guard let permission = permissionButtons.first(where: { $0.value === sender })?.key else { return }
        permissionFlowStage = nil
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

            let name = report.permission.displayName(in: strings.language)
            label.stringValue = "● \(report.statusTitle(in: strings.language))"
            label.textColor = report.status == .granted ? .systemGreen : .systemOrange
            button.title = strings[report.status == .granted ? .permissionOpenSettings : .permissionCheckAndGrant]
            button.toolTip = report.status == .granted
                ? strings.permissionTooltipGranted(name)
                : strings.permissionTooltipMissing(
                    usage: report.permission.usageDescription(in: strings.language),
                    permissionName: name
                )
        }

        let missing = reports.filter(\.needsAttention)
        guard Set(reports.map(\.permission)) == Set(VibeKeyPermission.allCases) else { return }

        permissionLabel.stringValue = missing.isEmpty
            ? strings[.permissionAllGranted]
            : strings.permissionMissing(missing.map { $0.permission.displayName(in: strings.language) })
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
