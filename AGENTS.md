# AGENTS.md — VibeKey Elements

Guidelines and architectural invariants for AI agents working in this repository.

---

## 🏛 Project Scope & Architecture

VibeKey Elements is a native Swift macOS hub and driver for the Ulanzi AU05 (VibeKey) device.

- `Sources/VibeKeyCore/`: Reusable driver library containing the 32-round TEA codec, USB HID framing, protocol packet builder/parser, and action performer.
- `Sources/vibekey-cli/`: Standalone terminal CLI binary (`vibekey`).
- `Sources/VibeKeyElementsApp/`: Native macOS status bar application (`VibeKeyElements`).
- `Tests/VibeKeyCoreTests/`: Unit tests, official vector validations, and ablation safety suites.

---

## ⚡ Hardware & Protocol Invariants

1. **HID Target Matching**:
   - Vendor ID: `0xFFF1`
   - Product ID: `0x00DD`
   - Primary Usage Page: `0xFFFC`
   - Primary Usage: `0x0001`
   - Report ID: `0x55` (Byte 0 of 64-byte reports)
2. **TEA Codec**:
   - 32 rounds, little-endian words, delta `0x9E3779B9`.
   - Key: `[0xCAA5BACA, 0xBC2A8A6D, 0xCA5A9EBA, 0x9BB88BCA]`.
   - Arithmetic MUST use wrapping operators (`&+`, `&-`).
3. **Report Framing**:
   - Output reports: 64 bytes total (`[0x55] + ciphertext.prefix(63)`).
   - Valid data payloads must be contained within the first 56 bytes (7 complete TEA blocks).

---

## 🔒 Concurrency & Safety Rules

- **Dedicated HID Queue**: All IOHIDManager setup, callbacks, heartbeat timers, and `IOHIDDeviceSetReport` calls must remain serialized on the internal `ioQueue`. Never schedule IOHIDManager on the main RunLoop.
- **Persistent Input Buffer**: The buffer supplied to `IOHIDDeviceRegisterInputReportCallback` must be allocated on the heap (`UnsafeMutablePointer<UInt8>`) and persist for the device session's lifetime. Never pass a local array or stack pointer to IOHID callbacks.
- **Non-blocking UI**: `ActionPerformer` key injections and delays (`usleep`) must execute exclusively on the background `actionQueue`. Never block the main thread.
- **Boundary Guards**:
  - `channel` for LED reports must be validated (`channel <= 3`) before calculating offsets.
  - `level` for noise reduction must be validated (`level <= 3`).

---

## 🧪 Testing & Verification

- Run `swift test` before submitting changes. All tests must pass with 0 failures.
- When adding protocol packets or hardware settings, provide matching test vectors and ablation safety tests in `Tests/VibeKeyCoreTests/`.

---

## 📦 Git & Commit Standards

- Commit subject: A single plain English sentence with the first letter capitalized, without conventional prefixes (such as `feat:`, `fix:`, `chore:`).
- Commit body: Bullet points describing the key file-level and behavior-level changes.
