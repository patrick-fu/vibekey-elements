# GitHub Actions CI 代码签名与 Apple 公证指南

本文档记录如何为 **VibeKey Elements** 配置 GitHub Actions CI，使用你的 **Developer ID Application** 证书进行自动代码签名，并通过 Apple 官方公证（Notarization）与装订（Staple），使其他 macOS 用户下载 DMG 后可以直接无警告打开运行。

---

## 🌟 核心原理解析

### 1. 为什么需要公证？
macOS 的 **Gatekeeper** 安全机制规定：
- 用户从浏览器或网络下载的任何 App 都会被系统自动打上隔离标记（`com.apple.quarantine`）；
- 未经开发者证书签名的 App 会提示“已损坏，无法打开”；
- 仅有普通证书（如 Apple Development）签名但未经过 Apple 官方公证盖戳的 App，仍会被 Gatekeeper 拦截；
- **只有经过 Developer ID Application 签名，且在 Apple 服务器公证（Notarization）成功并装订了票据（Staple）的 App，用户双击才能完全零拦截、直接运行。**

---

## 🔑 第一部分：导出 Developer ID 证书 (.p12)

在你的开发机上（已有证书 `"Developer ID Application: Patrick Fu (9N7UKH59LC)"`）：

### 1. 导出 `.p12` 文件
1. 打开 macOS **钥匙串访问**（Keychain Access）；
2. 在左侧选择 **登录**（login）钥匙串，在上方标签页切换到 **我的证书**（My Certificates）；
3. 找到并展开：
   `Developer ID Application: Patrick Fu (9N7UKH59LC)`
   *（注意：确保左侧的小三角展开，能看到其下属的私钥专用密钥）*；
4. 右键点击该证书项，选择 **导出“Developer ID Application: Patrick Fu (9N7UKH59LC)”...**；
5. 文件格式选择 **个人信息交换 (.p12)**，保存为例如 `DeveloperID.p12`；
6. 弹出的密码提示框中，输入一个用于保护该文件的强密码（记为 `P12_PASSWORD`）。

### 2. 生成 Base64 编码
在终端执行以下命令生成 Base64 字符串：

```bash
base64 -i DeveloperID.p12 | pbcopy
```
*（此时 Base64 字符串已自动复制到剪贴板）*

---

## 🛡 第二部分：准备 Apple 公证凭证（二选一）

Apple 公证服务（`notarytool`）支持以下两种身份验证方式：

### 方案 A（强烈推荐）：App Store Connect API Key (`.p8`)
* **优势**：专为 CI/CD 自动化设计，永不过期，不需要输入 2FA 短信验证码，安全性最高。
* **获取步骤**：
  1. 登录 [App Store Connect -> 用户与访问 -> 整合 / API 密钥](https://appstoreconnect.apple.com/access/integrations/api)；
  2. 点击 **+** 创建一个新密钥，名称填 `GitHub CI Notarization`，访问权限选择 **Developer** 或 **Admin**；
  3. 记录页面上显示的：
     - **Issuer ID**（例如：`57246542-96fe-1a63-e053-0824d011072a`）；
     - **密钥 ID (Key ID)**（例如：`2X9R4276CH`）；
  4. 点击 **下载 API 密钥**（文件名为 `AuthKey_2X9R4276CH.p8`，注意只能下载一次）；
  5. 将 `.p8` 文件转为 Base64：
     ```bash
     base64 -i AuthKey_2X9R4276CH.p8 | pbcopy
     ```

### 方案 B：Apple ID + App 专用密码 (App-Specific Password)
* **优势**：个人开发者操作门槛最低，1 分钟即可生成。
* **获取步骤**：
  1. 登录 [appleid.apple.com](https://appleid.apple.com/)；
  2. 进入 **登录和安全性** -> **App 专用密码**；
  3. 点击 **+** 生成一个专用密码，标签填 `VibeKey-Elements-CI`；
  4. 获得一个 16 位格式为 `xxxx-xxxx-xxxx-xxxx` 的字符串。

---

## ⚙️ 第三部分：配置 GitHub 仓库 Secrets

在 GitHub 仓库页面打开：
`Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`。

添加以下 Secrets：

| Secret 名称 | 必须性 | 说明 | 示例 |
| :--- | :---: | :--- | :--- |
| `APPLE_CERTIFICATE_P12_BASE64` | **必须** | 第一部分导出的 `.p12` 文件的 Base64 字符串 | `MIIKvgIBAzCC...` |
| `APPLE_CERTIFICATE_PASSWORD` | **必须** | 导出 `.p12` 时设置的保护密码 | `YourP12Password` |
| `APPLE_DEVELOPER_IDENTITY` | 可选 | 签名身份名称（CI 默认已内置您的名称） | `Developer ID Application: Patrick Fu (9N7UKH59LC)` |
| `APPLE_TEAM_ID` | 可选 | 您的 Apple Developer Team ID（默认为 `9N7UKH59LC`） | `9N7UKH59LC` |

#### 如果采用【方案 A（API Key）公证】：
| Secret 名称 | 必须性 | 说明 |
| :--- | :---: | :--- |
| `APPLE_API_KEY_ID` | 必须 | App Store Connect 生成的密钥 ID（如 `2X9R4276CH`） |
| `APPLE_API_ISSUER_ID` | 必须 | App Store Connect 页面上的 Issuer ID (UUID) |
| `APPLE_API_KEY_BASE64` | 必须 | `AuthKey_xxxx.p8` 文件的 Base64 编码 |

#### 如果采用【方案 B（App 专用密码）公证】：
| Secret 名称 | 必须性 | 说明 |
| :--- | :---: | :--- |
| `APPLE_ID` | 必须 | 您的 Apple 开发者账号邮箱（例如 `[REDACTED]`） |
| `APPLE_APP_SPECIFIC_PASSWORD` | 必须 | 在 appleid.apple.com 生成的 16 位专用密码 |

---

## 💡 CI 关键避坑与技术细节 (Critical Pitfalls)

1. **Keychain 交互弹窗死锁（No GUI Prompting）**：
   - GitHub Actions 的 macOS Runner 没有图形界面。如果导入证书后直接调用 `codesign`，系统会弹窗请求密码，导致 CI 进程永久阻塞直至超时被杀。
   - **解决方案**：在 CI 脚本中通过 `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"` 预先授权，彻底杜绝弹窗。
2. **强制 Hardened Runtime 强化运行时**：
   - Apple 公证服务器（Notarization Service）强制要求 App 必须开启强化运行时。
   - **解决方案**：签名命令必须附带 `--options runtime --timestamp`。
3. **临时钥匙串必须在 Job 结束时销毁**：
   - 即使签名失败，也不能在 Runner 上残留包含私钥的钥匙串。
   - **解决方案**：使用 GitHub Actions 的 `if: always()` 步骤执行 `security delete-keychain "$KEYCHAIN_PATH"`。
4. **公证后的离线票据装订 (Staple)**：
   - 仅公证成功还不够，必须对 DMG 执行 `xcrun stapler staple`，将公证凭证打包嵌入 DMG 镜像中，确保用户断网时依然能验证通过。
