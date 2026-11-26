import AppKit
import CoreGraphics
import VibeKeyCore

final class ShortcutRecorderField: NSButton {
    private let strings: VibeKeyStrings
    private let allowStandaloneModifier: Bool
    private var recordingBuffer: ShortcutRecordingBuffer
    private(set) var recordedAction: ActionConfig?
    var onRecorded: ((ActionConfig) -> Void)?
    private(set) var isRecording = false

    init(displayText: String, strings: VibeKeyStrings = .current, allowStandaloneModifier: Bool = false) {
        self.strings = strings
        self.allowStandaloneModifier = allowStandaloneModifier
        self.recordingBuffer = ShortcutRecordingBuffer(allowStandaloneModifier: allowStandaloneModifier)
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        title = displayText
        lineBreakMode = .byTruncatingMiddle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if isRecording {
            stopRecording(message: strings[.recorderCancelled])
        } else {
            startRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        if !isRecording { startRecording() }
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if event.keyCode == 0x35, ShortcutRecordingBuffer.modifiers(from: flags).isEmpty {
            stopRecording(message: strings[.recorderCancelled])
            return
        }
        complete(with: recordingBuffer.record(
            keyCode: CGKeyCode(event.keyCode),
            flags: flags
        ))
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        if !isRecording {
            guard !ShortcutRecordingBuffer.modifiers(from: flags).isEmpty else { return }
            startRecording()
        }

        if let shortcut = recordingBuffer.recordModifierChange(flags: flags) {
            complete(with: shortcut)
        } else {
            updateTitle(recordingBuffer.partialDisplay.isEmpty ? strings[.recorderPrompt] : recordingBuffer.partialDisplay)
        }
    }

    private func startRecording() {
        recordingBuffer = ShortcutRecordingBuffer(allowStandaloneModifier: allowStandaloneModifier)
        isRecording = true
        updateTitle(strings[.recorderPrompt])
    }

    private func stopRecording(message: String) {
        recordingBuffer = ShortcutRecordingBuffer(allowStandaloneModifier: allowStandaloneModifier)
        isRecording = false
        updateTitle(message)
    }

    private func complete(with shortcut: RecordedShortcut?) {
        guard let shortcut else {
            updateTitle(strings[.recorderUnsupported])
            return
        }

        recordedAction = shortcut.actionConfig
        recordingBuffer = ShortcutRecordingBuffer(allowStandaloneModifier: allowStandaloneModifier)
        isRecording = false
        updateTitle(shortcut.display)
        onRecorded?(shortcut.actionConfig)
    }

    private func updateTitle(_ text: String) {
        title = text
        needsDisplay = true
    }
}
