# VibeKey Elements

[English](README.md) | [简体中文](README_zh.md)

> **The ultimate developer-oriented hub for Ulanzi VibeKey (AU05) on macOS.**  
> *Zero vendor dynamic libraries. Pure-Swift TEA protocol. Real-time status bar dashboard. AI Agent hardware hooks. Full-featured CLI.*

---

## 🌟 Overview

**VibeKey Elements** is a lightweight, pure-Swift native macOS hub and driver designed specifically for the Ulanzi AU05 (VibeKey) macro controller and microphone. 

It provides complete control over hardware lighting, audio noise reduction, standby timeouts, and action dispatching, while bridging your desktop dial directly into your software development and AI coding workflows.

---

## ✨ Key Features

### 1. Pure-Swift TEA Protocol (Zero Vendor Binaries)
- **100% Clean-Room Implementation**: Built from scratch using native Swift.
- **Hardware-Native Cryptography**: Implements the 32-round Tiny Encryption Algorithm (TEA) over USB HID (Report ID `0x55`, 64 bytes).
- **Zero Proprietary Dependencies**: Completely free of closed-source vendor dynamic libraries (`.dylib`), ensuring total transparency, safety, and instant startup.

### 2. Interactive Menu Bar Dashboard & Key Flash
- **Live Battery & Charging Indicator**: Real-time battery percentage with dynamic charging state (`🎙 75%⚡`) in your macOS menu bar.
- **Millisecond Key Flash**: Provides instantaneous visual confirmation in the menu bar whenever you press a key or rotate the knob (`[K1]`, `[K2]`, `[K3]`, `[◀]`, `[▶]`, `[●]`), auto-reverting after 350ms.
- **Quick Controls**: Access microphone noise reduction, LED illumination modes, and custom standby delays directly from the status menu.

### 3. AI Coding Agent Hardware Hooks
- **Physical Agent Status Monitor**: Synchronize your desktop dial with AI coding agents (such as Codex, Claude Code, or local developer pipelines) via command line or API.
  - `thinking`: Gentle LED breathing pattern representing model inference.
  - `working`: Solid bright illumination while writing code or executing tools.
  - `error`: Alert flashing on task failures or interruptions.
  - `idle`: Automatic reset to default hardware management.

### 4. Comprehensive Hardware Control
- **Microphone Noise Reduction (NR)**: Instant hardware-level adjustment across 4 levels (0: Off, 1: Low, 2: Medium, 3: High).
- **Standby & Deep Sleep Timeouts**: Dynamically configure device standby delay (e.g. 5m, 15m, 30m, or never standby) and deep sleep intervals to prevent disconnect delays.
- **4-Channel LED Management**: Full control over solid, breathing, off, and automatic hardware-restored modes.

### 5. Multi-Action Execution Engine
- **Keyboard Shortcuts & Sequences**: Emulate single keys, complex chords (⌘, ⌥, ⌃, ⇧), and dedicated `Fn` key toggles.
- **Smooth Mouse Scrolling**: High-precision line-based vertical mouse wheel scrolling.
- **Asynchronous Shell Commands**: Trigger arbitrary terminal scripts and background workflows (`$ cmd`) on button events without freezing the UI.

### 6. Full-Featured `vibekey` CLI Suite
- Manage all device capabilities directly from terminal scripts, Alfred/Raycast workflows, or automation daemons.

---

## 🚀 Quick Start

### Building from Source

Requirements: macOS 13.0+ and Xcode 15+ / Swift 5.9+.

```bash
git clone https://github.com/patrick-fu/vibekey-elements.git
cd vibekey-elements

# Build both CLI and Menu Bar App
swift build -c release

# Run comprehensive test suite
swift test
```

### Using the CLI (`vibekey`)

The compiled CLI binary is located at `.build/release/vibekey`:

```bash
# Check device status & query battery
vibekey status

# Set microphone hardware noise reduction to medium
vibekey set-nr 2

# Set standby timeout to 30 minutes (1800s)
vibekey set-standby 1800

# Set LED channel 0 to breathing mode
vibekey led 0 breathing 80

# Reset LED to default hardware control
vibekey reset-led

# Trigger AI Coding Agent state hook
vibekey hook thinking
vibekey hook idle
```

### Running the Menu Bar App

```bash
open .build/release/VibeKeyElements
```

---

## 🛠 Architecture

```text
vibekey-elements/
├── Sources/
│   ├── VibeKeyCore/          # Pure-Swift USB HID driver, 32-round TEA codec & action performer
│   ├── vibekey-cli/          # Unified terminal command-line tool (`vibekey`)
│   └── VibeKeyElementsApp/   # Menu Bar status item & user interface
└── Tests/
    └── VibeKeyCoreTests/     # Protocol validation, unit tests, and ablation safety suites
```

---

## 📄 License

MIT License © 2026 Patrick Fu.
