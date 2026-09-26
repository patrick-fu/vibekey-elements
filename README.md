# VibeKey Elements

> **The ultimate developer-oriented hub for Ulanzi VibeKey (AU05) on macOS.**  
> *Zero vendor dylibs. Pure-Swift TEA protocol. Real-time status bar dashboard. AI Agent hardware hooks. Full-featured CLI.*

---

## 🌟 Why VibeKey Elements?

The official **Ulanzi Studio** is a bulky (~300MB) Electron/Qt suite with unnecessary live-streaming and plugin bloat. Meanwhile, community alternatives like **vibekey-lite** cut too much—stripping away battery indicators, visual feedback, microphone controls, and LED management to serve solely as a barebones key-remapper.

**VibeKey Elements** strikes the perfect balance for developers:
- **Clean-Room Open Source**: 100% pure Swift reverse-engineered USB HID implementation using the 32-round TEA algorithm. Zero dependence on closed-source vendor binaries (`kwdm.dylib`).
- **Interactive Menu Bar Dashboard**: Real-time battery percentage and charging indicator (`🎙 70%⚡`) with millisecond-precision key flash animations (`[K1]`, `[◀]`, `[▶]`, `[●]`).
- **AI Coding Agent Hardware Hooks**: Transform your desktop dial into a physical status monitor for AI coding agents (Codex, Claude Code) with dedicated lighting states (`thinking`, `working`, `error`, `idle`).
- **Full Hardware Control**: 4-channel LED control (solid, breathing, off, hardware auto), 4-level microphone noise reduction (NR 0–3), and custom standby/sleep timeout management.
- **Developer Ecosystem & CLI**: Rich `vibekey` command-line tool for scripting, terminal integration, and shell-action dispatching.

---

## 📊 Feature Comparison

| Feature | Official Ulanzi Studio | Community vibekey-lite | **VibeKey Elements** |
| :--- | :---: | :---: | :---: |
| **Footprint / Memory** | Heavy (~300MB) | Light (~15MB) | **Ultra-light (~15MB)** |
| **Vendor Dylib Dependency** | Proprietary `kwdm.dylib` | None (Clean TEA) | **None (Pure-Swift Clean TEA)** |
| **Status Bar Battery & Charging** | ❌ (Window only) | ❌ (Static icon) | **✅ Real-time (`🎙 70%⚡`)** |
| **Keypress Visual Feedback** | ❌ None | ❌ None | **✅ Key Flash (`[K1]`, `[◀]`, etc.)** |
| **Microphone Noise Reduction** | ✅ In-app | ❌ None | **✅ 4 Levels (0/1/2/3) + CLI** |
| **Standby & Deep Sleep Config** | ✅ Fixed options | ❌ Read-only display | **✅ Dynamic (1–30m / Never)** |
| **4-Channel LED Management** | Limited | ❌ None | **✅ Full Control + `reset-led`** |
| **AI Coding Agent Hooks** | ❌ None | ❌ None | **✅ Hardware State Sync** |
| **Command-Line Interface (CLI)**| ❌ None | ❌ None | **✅ `vibekey` CLI Suite** |
| **Action Execution Engine** | Shortcuts only | Keystrokes only | **✅ Shortcuts, Mouse Scroll, Shell `$ cmd`** |

---

## 🛠 Architecture & Components

```text
vibekey-elements/
├── Sources/
│   ├── VibeKeyCore/          # Clean-room USB HID engine & 32-round TEA codec
│   ├── vibekey-cli/          # Unified terminal command-line tool (`vibekey`)
│   └── VibeKeyElementsApp/   # Menu Bar status item & user interface
└── Tests/
    └── VibeKeyCoreTests/     # Protocol vector validation & packet tests
```

---

## 📄 License

MIT License © 2026 Patrick Fu.
