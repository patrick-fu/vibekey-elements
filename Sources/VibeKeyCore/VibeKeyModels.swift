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
}

public enum ButtonPhase: String, Codable, Sendable {
    case down
    case up
}

public enum DeviceEvent: Equatable, Sendable {
    case key(control: InputControl, phase: ButtonPhase)
    case power(VibeKeyPowerResponse)
}

public struct VibeKeyBatteryStatus: Equatable, Codable, Sendable {
    public let percent: UInt16
    public let voltageMillivolts: UInt16
    public let isCharging: Bool

    public init(percent: UInt16, voltageMillivolts: UInt16, isCharging: Bool) {
        self.percent = percent
        self.voltageMillivolts = voltageMillivolts
        self.isCharging = isCharging
    }
}

public enum VibeKeyPowerResponse: Equatable, Sendable {
    case battery(VibeKeyBatteryStatus)
    case standbyTime(seconds: UInt32)
    case sleepTime(seconds: UInt32)
}

public enum LEDMode: String, Codable, CaseIterable, Sendable {
    case solid = "solid"
    case breathing = "breathing"
    case off = "off"
    case auto = "auto"
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

    public init(
        topButton: ActionConfig = .keySequence(keys: ["fn"]),
        middleButton: ActionConfig = .keySequence(keys: ["return"]),
        bottomButton: ActionConfig = .keySequence(keys: ["command", "delete"]),
        knobLeft: ActionConfig = .mouseWheel(direction: .down),
        knobRight: ActionConfig = .mouseWheel(direction: .up),
        knobPress: ActionConfig = .keySequence(keys: ["option", "command", "a"])
    ) {
        self.topButton = topButton
        self.middleButton = middleButton
        self.bottomButton = bottomButton
        self.knobLeft = knobLeft
        self.knobRight = knobRight
        self.knobPress = knobPress
    }

    enum CodingKeys: String, CodingKey {
        case topButton, middleButton, bottomButton, knobLeft, knobRight, knobPress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.topButton = try container.decodeIfPresent(ActionConfig.self, forKey: .topButton) ?? .keySequence(keys: ["fn"])
        self.middleButton = try container.decodeIfPresent(ActionConfig.self, forKey: .middleButton) ?? .keySequence(keys: ["return"])
        self.bottomButton = try container.decodeIfPresent(ActionConfig.self, forKey: .bottomButton) ?? .keySequence(keys: ["command", "delete"])
        self.knobLeft = try container.decodeIfPresent(ActionConfig.self, forKey: .knobLeft) ?? .mouseWheel(direction: .down)
        self.knobRight = try container.decodeIfPresent(ActionConfig.self, forKey: .knobRight) ?? .mouseWheel(direction: .up)
        self.knobPress = try container.decodeIfPresent(ActionConfig.self, forKey: .knobPress) ?? .keySequence(keys: ["option", "command", "a"])
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
}
