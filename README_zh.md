# VibeKey Elements

[English](README.md) | [简体中文](README_zh.md)

> **专为优篮子 Ulanzi VibeKey (AU05) 打造的 macOS 极客硬件中枢。**  
> *纯血 Swift 实现 · 零闭源动态库 · 状态栏交互式仪表盘 · AI Agent 硬件状态联动 · 全功能 CLI 工具箱*

---

## 🌟 项目简介

**VibeKey Elements** 是一款专为优篮子 AU05（商品名 VibeKey）定制的轻量级原生 macOS 硬件控制中枢与驱动。

它提供了对机身灯光、麦克风硬件降噪、待机休眠超时以及物理按键/旋钮动作的完整接管能力，并创造性地打通了物理硬件与现代 AI 编程助手（如 Codex、Claude Code）及自动化工作流的联动。

---

## ✨ 核心特性

### 1. 纯血 Swift TEA 协议（零闭源动态库依赖）
- **100% 独立开源实现**：完全使用 Swift 原生重写。
- **底层硬件加解密**：原生实现 32 轮微型加密算法（TEA）处理 USB HID 通讯（Report ID `0x55`，64 字节报文）。
- **零黑盒依赖**：彻底摆脱了任何闭源外部动态库（`.dylib`），完全开源合规、内存占用极低且启动迅速。

### 2. 悬浮设置面板 (Popover) 与状态栏交互仪表盘
- **沉浸式控制面板**：点击菜单栏图标即可唤出原生悬浮面板（NSPopover），选择按键配置或参数时**窗口常驻不关闭**，交互丝滑。
- **配置勾选状态直观呈现**：无论在悬浮面板下拉框还是右键快捷菜单中，当前生效的按键动作与配置均有明确勾选标识（Checkmark）。
- **硬件信息全景展示**：实时展示设备连接状态、固件版本、机身序列号（SN）、精准电量百分比、电压（mV）及充电动态标识（⚡）。
- **按键视觉闪现反馈**：按下物理按键或旋转旋钮时，状态栏图标瞬时闪现按键标识（如 `[K1]`、`[◀]` 等），提供即时的盲操确认感。
- **实时电量与充电状态**：在 macOS 顶部菜单栏动态显示电量百分比与充电标识（如 `🎙 75%⚡`）。
- **按键视觉闪现反馈**：按下按键或旋转旋钮时，状态栏图标毫秒级瞬时变更为 `[K1]`、`[K2]`、`[K3]`、`[◀]`、`[▶]`、`[●]`，并在 350 毫秒后自动恢复，提供极为爽快的盲操确认感。
- **快捷控制菜单**：直接从状态栏下拉菜单一键切换降噪档位、LED 模式及待机时间。

### 3. AI Coding Agent 硬件状态联动 (Hooks)
- **物理状态指示灯**：让桌面的小硬件化身为 AI 编程助手（Codex、Claude Code 等）的物理状态指示器：
  - `thinking`：慢速呼吸灯，表示模型正在思考推理。
  - `working`：高亮常亮，表示正在编写代码或调用工具。
  - `error`：红光警报闪烁，表示任务遇到报错或中断。
  - `idle`：任务完成待命，自动恢复出厂硬件自管。

### 4. 完整的硬件控制权
- **麦克风硬件降噪 (NR)**：支持 4 档硬件级降噪即时切换（0 关 / 1 弱 / 2 中 / 3 强）。
- **待机与深度休眠超时**：支持自由配置设备 Standby 待机延迟（如 5 分钟、15 分钟、30 分钟或从不待机）与睡眠时间，彻底解决官方默认 5 分钟自动休眠导致的按键唤醒延迟。
- **4 通道 LED 独立控制**：支持常亮、呼吸、关灯以及一键复位硬件自管（`reset-led`）。

### 5. 多类型动作执行引擎
- **按键序列与快捷键**：支持单键、组合修饰键（⌘、⌥、⌃、⇧）及专属的 `Fn` 单键触发。
- **平滑鼠标滚轮**：高精度模拟行级平滑上下滚动。
- **异步 Shell 脚本执行**：按键可直接触发后台终端命令（`$ cmd`），与系统级脚本或 Raycast 联动且不卡顿 UI。

### 6. 全功能 `vibekey` 终端 CLI
- 提供功能完备的命令行工具，方便嵌入 Shell 脚本、Alfred/Raycast 动作或终端自动化。

---

## 🚀 快速上手

### 📥 直接下载（Apple 官方公证 DMG）

从 GitHub Releases 直接下载最新已通过苹果公证的安装包：
- 📦 **[下载 VibeKey-Elements-macOS-arm64.dmg](https://github.com/patrick-fu/vibekey-elements/releases/latest/download/VibeKey-Elements-macOS-arm64.dmg)**

*(已通过 Apple Developer ID 签名并盖戳公证，双击即可无警告直接运行。)*

### 🛠 源码编译

环境要求：macOS 13.0+，Xcode 15+ / Swift 5.9+。

```bash
git clone https://github.com/patrick-fu/vibekey-elements.git
cd vibekey-elements

# 编译 CLI 工具与 Menu Bar 应用
swift build -c release

# 运行完整单元测试与消融实验
swift test
```

### CLI 命令行工具 (`vibekey`)

编译后的 CLI 可执行文件位于 `.build/release/vibekey`：

```bash
# 查看硬件连接状态并查询电量
vibekey status

# 设置麦克风硬件降噪为中档 (2)
vibekey set-nr 2

# 设置待机超时为 30 分钟 (1800 秒)
vibekey set-standby 1800

# 将 LED 0 通道设为呼吸灯模式
vibekey led 0 breathing 80

# 复位 LED 恢复硬件自管
vibekey reset-led

# 触发 AI Coding Agent 状态联动
vibekey hook thinking
vibekey hook idle
```

### 运行菜单栏应用

```bash
open .build/release/VibeKeyElements
```

---

## 🛠 架构设计

```text
vibekey-elements/
├── Sources/
│   ├── VibeKeyCore/          # 核心引擎：USB HID 通讯、32 轮 TEA 编解码与动作分发器
│   ├── vibekey-cli/          # 统一终端命令行工具 (`vibekey`)
│   └── VibeKeyElementsApp/   # Menu Bar 状态栏应用与控制面板
└── Tests/
    └── VibeKeyCoreTests/     # 协议向量核验、单元测试与安全性消融实验套件
```

---

## 📄 开源许可

本项目采用 MIT 许可证 © 2026 Patrick Fu.
