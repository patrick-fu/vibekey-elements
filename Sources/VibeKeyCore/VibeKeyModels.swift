import Foundation

public enum InputControl: String, Codable, CaseIterable, Sendable {
    case topButton = "topButton"
    case middleButton = "middleButton"
    case bottomButton = "bottomButton"
    case knobPress = "knobPress"
    case knobLeft = "knobLeft"
    case knobRight = "knobRight"

    public var displayLabel: String {
        switch self {
        case .topButton: return "K1"
        case .middleButton: return "K2"
        case .bottomButton: return "K3"
        case .knobPress: return "●"
        case .knobLeft: return "◀"
        case .knobRight: return "▶"
        }
    }

    public var displayName: String {
        switch self {
        case .topButton: return "上键 (K1)"
        case .middleButton: return "中键 (K2)"
        case .bottomButton: return "下键 (K3)"
        case .knobPress: return "旋钮按下"
        case .knobLeft: return "旋钮左旋"
        case .knobRight: return "旋钮右旋"
        }
    }
}

public enum ButtonPhase: String, Codable, Sendable {
    case down
    case up
}

public enum DeviceEvent: Equatable, Sendable {
    case key(control: InputControl, phase: ButtonPhase)
    case power(VibeKeyPowerResponse)
    case notice(VibeKeyNotice)
}

public enum VibeKeyNotice: Equatable, Sendable {
    case standby(isStandby: Bool)
    case active(isActive: Bool)
    case powerOn
}

public struct VibeKeyBatteryStatus: Equatable, Codable, Sendable {
    public let percent: UInt16
    public let voltageMillivolts: UInt16
    public let isCharging: Bool
    public let isFullyCharged: Bool

    public init(
        percent: UInt16,
        voltageMillivolts: UInt16,
        isCharging: Bool,
        isFullyCharged: Bool = false
    ) {
        self.percent = percent
        self.voltageMillivolts = voltageMillivolts
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
    }
}

public struct VibeKeyDeviceInfoSnapshot: Equatable, Sendable {
    public var isConnected: Bool
    public var firmwareVersion: String?
    public var serialNumber: String?
    public var battery: VibeKeyBatteryStatus?
    public var standbyTimeSeconds: UInt32?
    public var sleepTimeSeconds: UInt32?
    public var isStandby: Bool
    public var isDeviceOn: Bool?
    public var micNoiseReduction: UInt8?
    public var micEnabled: Bool?
    public var ledMode: LEDMode?

    public init(
        isConnected: Bool = false,
        firmwareVersion: String? = nil,
        serialNumber: String? = nil,
        battery: VibeKeyBatteryStatus? = nil,
        standbyTimeSeconds: UInt32? = nil,
        sleepTimeSeconds: UInt32? = nil,
        isStandby: Bool = false,
        isDeviceOn: Bool? = nil,
        micNoiseReduction: UInt8? = nil,
        micEnabled: Bool? = nil,
        ledMode: LEDMode? = nil
    ) {
        self.isConnected = isConnected
        self.firmwareVersion = firmwareVersion
        self.serialNumber = serialNumber
        self.battery = battery
        self.standbyTimeSeconds = standbyTimeSeconds
        self.sleepTimeSeconds = sleepTimeSeconds
        self.isStandby = isStandby
        self.isDeviceOn = isDeviceOn
        self.micNoiseReduction = micNoiseReduction
        self.micEnabled = micEnabled
        self.ledMode = ledMode
    }
}

public enum VibeKeyPowerResponse: Equatable, Sendable {
    case battery(VibeKeyBatteryStatus)
    case standbyTime(seconds: UInt32)
    case sleepTime(seconds: UInt32)
    case micNR(level: UInt8)
    case micEnabled(Bool)
}

public enum LEDMode: String, Codable, CaseIterable, Sendable {
    case auto = "auto"
    case solid = "solid"
    case breathing = "breathing"
    case off = "off"

    public var displayName: String {
        switch self {
        case .auto: return "硬件自管 (出厂默认)"
        case .solid: return "柔和常亮"
        case .breathing: return "优雅呼吸"
        case .off: return "指示灯全灭"
        }
    }
}

public enum AgentHookState: String, Codable, CaseIterable, Sendable {
    case thinking = "thinking"
    case working = "working"
    case error = "error"
    case idle = "idle"
}

public enum MouseWheelDirection: String, Codable, Sendable {
    case up
    case down
}

public enum PresetAction: String, CaseIterable, Codable, Sendable {
    case fn = "fn"
    case enter = "enter"
    case cmdDelete = "cmdDelete"
    case scrollUp = "scrollUp"
    case scrollDown = "scrollDown"
    case selectAll = "selectAll"
    case copy = "copy"
    case paste = "paste"
    case undo = "undo"
    case playPause = "playPause"
    case mute = "mute"
    case volumeUp = "volumeUp"
    case volumeDown = "volumeDown"
    case none = "none"

    public var displayName: String {
        switch self {
        case .fn: return "Fn 键"
        case .enter: return "Enter (回车)"
        case .cmdDelete: return "⌘ + Delete (删除)"
        case .scrollUp: return "滚轮向上 (Scroll Up)"
        case .scrollDown: return "滚轮向下 (Scroll Down)"
        case .selectAll: return "⌘A (全选)"
        case .copy: return "⌘C (复制)"
        case .paste: return "⌘V (粘贴)"
        case .undo: return "⌘Z (撤销)"
        case .playPause: return "播放 / 暂停"
        case .mute: return "静音"
        case .volumeUp: return "音量 +"
        case .volumeDown: return "音量 -"
        case .none: return "无动作"
        }
    }

    public var actionConfig: ActionConfig {
        switch self {
        case .fn: return .keySequence(keys: ["fn"])
        case .enter: return .keySequence(keys: ["return"])
        case .cmdDelete: return .keySequence(keys: ["command", "delete"])
        case .scrollUp: return .mouseWheel(direction: .up)
        case .scrollDown: return .mouseWheel(direction: .down)
        case .selectAll: return .keySequence(keys: ["command", "a"])
        case .copy: return .keySequence(keys: ["command", "c"])
        case .paste: return .keySequence(keys: ["command", "v"])
        case .undo: return .keySequence(keys: ["command", "z"])
        case .playPause: return .keySequence(keys: ["space"])
        case .mute: return .shellCommand(command: "osascript -e 'set volume output muted not (output muted of (get volume settings))'")
        case .volumeUp: return .shellCommand(command: "osascript -e 'set volume output volume ((output volume of (get volume settings)) + 6)'")
        case .volumeDown: return .shellCommand(command: "osascript -e 'set volume output volume ((output volume of (get volume settings)) - 6)'")
        case .none: return .keySequence(keys: [])
        }
    }
}

public enum ActionConfig: Codable, Equatable, Sendable {
    case keySequence(keys: [String])
    case mouseWheel(direction: MouseWheelDirection)
    case shellCommand(command: String)

    enum CodingKeys: String, CodingKey {
        case type, keys, direction, command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "keySequence":
            let keys = try container.decode([String].self, forKey: .keys)
            self = .keySequence(keys: keys)
        case "mouseWheel":
            let direction = try container.decode(MouseWheelDirection.self, forKey: .direction)
            self = .mouseWheel(direction: direction)
        case "shellCommand":
            let command = try container.decode(String.self, forKey: .command)
            self = .shellCommand(command: command)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown action type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .keySequence(keys):
            try container.encode("keySequence", forKey: .type)
            try container.encode(keys, forKey: .keys)
        case let .mouseWheel(direction):
            try container.encode("mouseWheel", forKey: .type)
            try container.encode(direction, forKey: .direction)
        case let .shellCommand(command):
            try container.encode("shellCommand", forKey: .type)
            try container.encode(command, forKey: .command)
        }
    }
}

public struct VibeKeyConfiguration: Codable, Equatable, Sendable {
    public var topButton: ActionConfig
    public var middleButton: ActionConfig
    public var bottomButton: ActionConfig
    public var knobLeft: ActionConfig
    public var knobRight: ActionConfig
    public var knobPress: ActionConfig
    public var micNoiseReduction: UInt8
    public var micEnabled: Bool
    public var ledMode: LEDMode
    public var standbySeconds: UInt32
    public var sleepSeconds: UInt32
    public var longConnectedMode: Bool

    public init(
        topButton: ActionConfig = .keySequence(keys: ["fn"]),
        middleButton: ActionConfig = .keySequence(keys: ["return"]),
        bottomButton: ActionConfig = .keySequence(keys: ["command", "delete"]),
        knobLeft: ActionConfig = .mouseWheel(direction: .down),
        knobRight: ActionConfig = .mouseWheel(direction: .up),
        knobPress: ActionConfig = .keySequence(keys: ["option", "command", "a"]),
        micNoiseReduction: UInt8 = 0,
        micEnabled: Bool = true,
        ledMode: LEDMode = .auto,
        standbySeconds: UInt32 = 300,
        sleepSeconds: UInt32 = 3600,
        longConnectedMode: Bool = false
    ) {
        self.topButton = topButton
        self.middleButton = middleButton
        self.bottomButton = bottomButton
        self.knobLeft = knobLeft
        self.knobRight = knobRight
        self.knobPress = knobPress
        self.micNoiseReduction = micNoiseReduction
        self.micEnabled = micEnabled
        self.ledMode = ledMode
        self.standbySeconds = standbySeconds
        self.sleepSeconds = sleepSeconds
        self.longConnectedMode = longConnectedMode
    }

    enum CodingKeys: String, CodingKey {
        case topButton, middleButton, bottomButton, knobLeft, knobRight, knobPress
        case micNoiseReduction, micEnabled, ledMode, standbySeconds, sleepSeconds
        case longConnectedMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.topButton = try container.decodeIfPresent(ActionConfig.self, forKey: .topButton) ?? .keySequence(keys: ["fn"])
        self.middleButton = try container.decodeIfPresent(ActionConfig.self, forKey: .middleButton) ?? .keySequence(keys: ["return"])
        self.bottomButton = try container.decodeIfPresent(ActionConfig.self, forKey: .bottomButton) ?? .keySequence(keys: ["command", "delete"])
        self.knobLeft = try container.decodeIfPresent(ActionConfig.self, forKey: .knobLeft) ?? .mouseWheel(direction: .down)
        self.knobRight = try container.decodeIfPresent(ActionConfig.self, forKey: .knobRight) ?? .mouseWheel(direction: .up)
        self.knobPress = try container.decodeIfPresent(ActionConfig.self, forKey: .knobPress) ?? .keySequence(keys: ["option", "command", "a"])
        self.micNoiseReduction = try container.decodeIfPresent(UInt8.self, forKey: .micNoiseReduction) ?? 0
        self.micEnabled = try container.decodeIfPresent(Bool.self, forKey: .micEnabled) ?? true
        self.ledMode = try container.decodeIfPresent(LEDMode.self, forKey: .ledMode) ?? .auto
        self.standbySeconds = try container.decodeIfPresent(UInt32.self, forKey: .standbySeconds) ?? 300
        self.sleepSeconds = try container.decodeIfPresent(UInt32.self, forKey: .sleepSeconds) ?? 3600
        self.longConnectedMode = try container.decodeIfPresent(Bool.self, forKey: .longConnectedMode) ?? false
    }

    public func action(for control: InputControl) -> ActionConfig {
        switch control {
        case .topButton: return topButton
        case .middleButton: return middleButton
        case .bottomButton: return bottomButton
        case .knobLeft: return knobLeft
        case .knobRight: return knobRight
        case .knobPress: return knobPress
        }
    }

    public mutating func setAction(_ action: ActionConfig, for control: InputControl) {
        switch control {
        case .topButton: topButton = action
        case .middleButton: middleButton = action
        case .bottomButton: bottomButton = action
        case .knobLeft: knobLeft = action
        case .knobRight: knobRight = action
        case .knobPress: knobPress = action
        }
    }
}
