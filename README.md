# VibeKey Elements

[English](README.md) | [简体中文](README_zh.md)

> **The ultimate developer-oriented hub for Ulanzi VibeKey (AU05) on macOS.**  
> *Zero vendor dynamic libraries. Pure-Swift TEA protocol. Real-time status bar dashboard. AI Agent hardware hooks. Full-featured CLI.*

<p align="center">
  <img src="docs/screenshots/menu-bar-panel.png" width="420" alt="VibeKey Elements Menu Bar Panel">
</p>

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

### 2. Native Settings Popover & Status Bar Dashboard
- **Persistent Settings Panel**: Left-clicking the status bar item opens a native AppKit Popover that **stays open during option adjustments**, eliminating sudden window dismissals.
- **Explicit Checkmark States**: Clear selection checkmarks for every input mapping, noise reduction level, and LED mode across both the popover and right-click context menu.
- **Comprehensive Hardware Insights**: Live presentation of firmware version, hardware serial number (SN), exact battery percentage, voltage (mV), and dynamic charging indicator (⚡).
- **Millisecond Key Flash**: Instant visual feedback in the menu bar (`[K1]`, `[◀]`, `[●]`, etc.) upon physical clicks or knob rotations.

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

### 5. Ultra-Low Power & Deep Sleep Management (Zero Downlink RF Emissions)
- **Eliminates Overnight Battery Drain**: Solves the common hardware issue where continuous host-side polling and heartbeats over the 2.4G dongle prevent the AU05 from sleeping overnight.
- **Zero Downlink RF Traffic in Standby**: When the AU05 is idle for 5 minutes (Standby), powered down, or when macOS enters sleep, VibeKey Elements halts all recurring heartbeats and query packets, allowing the device MCU and 2.4G transceiver to rest in true microamp-level (~15–30 µA) deep sleep.
- **Optional Long-Connect Mode**: Keeps the regular 0.8s heartbeat and suppresses idle standby for uninterrupted work sessions; macOS sleep still switches to zero-downlink standby.
- **Instant Wake on Touch**: Tapping any button or turning the dial immediately wakes the device and re-establishes host communication in milliseconds.
- **Power-Aware Battery Polling**: Battery telemetry interval is relaxed to 180s (3 minutes) during active use, slashing unnecessary RF traffic by 92%.
- **macOS System Sleep Coordination**: Full lifecycle integration with `NSWorkspace.willSleepNotification` and `didWakeNotification`.

### 6. Multi-Action Execution Engine
- **Keyboard Shortcuts & Sequences**: Emulate single keys, complex chords (⌘, ⌥, ⌃, ⇧), and dedicated `Fn` key toggles.
- **Smooth Mouse Scrolling**: High-precision line-based vertical mouse wheel scrolling.
- **Asynchronous Shell Commands**: Trigger arbitrary terminal scripts and background workflows (`$ cmd`) on button events without freezing the UI.

### 7. Sparkle 2 Auto-Update
- **Automatic Background Checks**: Periodically checks for updates every 7 days in the background (`SUScheduledCheckInterval = 604800`).
- **User Choice & Control**: Allows skipping versions, postponing reminders, or manual checking via "Check for Updates..." in the status bar context menu and settings panel.
- **Cryptographic Security**: Enforces Ed25519 public key signature verification (`SUPublicEDKey`) for all binary downloads and feed items.

### 8. Full-Featured `vibekey` CLI Suite
- Manage all device capabilities directly from terminal scripts, Alfred/Raycast workflows, or automation daemons.

---

## 🚀 Quick Start

### 📥 Direct Download (Apple Notarized DMG)

Download the latest signed and notarized DMG directly from GitHub Releases:
- 📦 **[Download VibeKey-Elements-macOS-arm64.dmg](https://github.com/patrick-fu/vibekey-elements/releases/latest/download/VibeKey-Elements-macOS-arm64.dmg)**

*(Verified and notarized by Apple; no Gatekeeper bypass or quarantine removal required.)*

### 🛠 Building from Source

Requirements: macOS 13.0+ and Xcode 15+ / Swift 5.9+.

```bash
git clone https://github.com/patrick-fu/vibekey-elements.git
cd vibekey-elements

# Build both CLI and Menu Bar App
swift build -c release

# Run comprehensive test suite
swift test
```

### 🔍 Verifying Standby Power Saving & Zero-Downlink Operation

To eliminate overnight battery drain, VibeKey Elements halts all recurring 2.4G RF downlink packets (heartbeats and polling) once the device enters standby or when macOS sleeps. You can verify this behavior anytime using macOS Unified Logging:

```bash
# 1. Stream live power state transitions in real time
log stream --predicate 'subsystem == "com.patrickfu.vibekey"' --level debug

# 2. Query historical power events from the past 12 hours
log show --predicate 'subsystem == "com.patrickfu.vibekey" and category == "Power"' --last 12h
```

**Expected Log Indicators**:
- Entering standby: `Entering power saving mode (isStandby: true, reason: InactivityTimeout). Halting heartbeat & polling timers.`
- Host sleep: `macOS host sleep/power-off notification received. Forcing standby power saving mode.`
- Host wake: `Maintaining zero-downlink standby to prevent DarkWake RF wakeups.`
- Instant wake: `Physical input detected (k1) while in standby. Resuming.`
- Status Bar: A `💤` icon appears next to the battery percentage while the device is in low-power standby.

---

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
