# VoxLink AI

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS%2014.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)

A native macOS voice input assistant built with Swift and SwiftUI. Press a hotkey, speak, and let AI transcribe and polish your words — then auto-type the result into any app.

<div align="center">

https://github.com/user-attachments/assets/placeholder

*If the video above doesn't load, [download the demo (2 MB)](assets/demo.mp4).*

</div>

<details>
<summary>🇨🇳 中文说明</summary>

## 简介

VoxLink AI 是一款原生 macOS 语音输入助手。按住快捷键说话，AI 自动将语音转为文字并润色，然后输入到当前应用中。

> 演示视频见上方，或[直接下载 (2 MB)](assets/demo.mp4)。

### 功能特性

- **实时语音识别** — 按住 Option 键说话，松开即发送
- **AI 文本润色** — 自动优化语音转文字结果（去除口语化表达、修正语法）
- **自动输入** — 识别结果自动输入到当前聚焦的应用
- **悬浮胶囊 UI** — 深色磨砂玻璃风格，实时声波可视化和转录预览
- **BYOK 模式** — 自备 API Key，数据安全可控

### 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Xcode 15.0+
- Apple Silicon (M1/M2/M3) 或 Intel Mac

### 快速开始

请参考下方英文部分的 [Getting Started](#getting-started) 章节，步骤完全一致。

### 快速安装 (DMG)

从 [GitHub Releases](https://github.com/axzml/VoxLinkAI_Client/releases) 下载最新 `.dmg`，打开后将 VoxLink AI 拖入 Applications 即可。

> **macOS Gatekeeper 提示：** 由于应用未经 Apple 公证，首次打开时 macOS 可能提示"无法验证开发者"。解决方法：右键点击应用 -> 选择"打开" -> 在弹窗中点击"打开"。仅需操作一次。

启动后在设置中填入阿里云 API Key 即可使用。

### 从源码编译

1. 复制 `Secrets.example.plist` 为 `Secrets.plist`（默认 `USE_MOCK_AUTH=true`，无需 Supabase）
2. 在 Xcode 中选择你的开发者 Team，然后编译运行
3. 首次运行需授权：辅助功能（全局快捷键）和麦克风权限
4. 在应用设置中填入阿里云 API Key
5. 如需接入自己的后端，在 `Secrets.plist` 中配置 `API_BASE_URL` 和 `WEBSITE_BASE_URL`

详细配置说明见 [CONFIGURATION.md](VoxLinkAI/VoxLinkAI/Core/Auth/CONFIGURATION.md)。

### 首次编译注意事项

**Keychain 弹窗：** 首次编译运行时，系统会弹窗要求输入系统密码以访问 Keychain。这是正常的 macOS 开发行为（因为 app 需要在 Keychain 中存储 API Key），不涉及任何隐私问题。点击 **"始终允许"** 即可。

**权限授权：** 启动后系统会依次请求麦克风和辅助功能（Accessibility）权限。

**辅助功能权限问题：** 首次授权辅助功能后，快捷键（Option）可能无法响应，日志显示 `Accessibility permissions not granted, will retry...`。这是 macOS 对开发签名 app 的已知行为，解决方法：

1. 在终端中重置权限：
   ```bash
   tccutil reset Accessibility com.voxlinkai.VoxLinkAI
   ```
2. 完全退出 app（`Cmd + Q` 或杀进程）
3. 在 Xcode 中重新编译运行（`Cmd + R`）
4. 系统会再次弹出辅助功能授权 — 这次授权后即可正常工作

> **提示：** 如果在系统设置中尝试手动移除 VoxLinkAI，减号按钮可能是灰色不可点击的。使用上述 `tccutil` 命令是可靠的重置方式。

此操作只需做一次（除非 Clean Build，因为那会改变代码签名）。

### 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Option` (按住) | 开始录音，松开结束并发送 |
| `Escape` | 取消当前录音 |

</details>

## Features

- **Real-time Speech Recognition** — Hold the Option key to speak, release to send
- **AI Text Polishing** — Automatically refines speech-to-text output (removes filler words, fixes grammar)
- **Auto-typing** — Transcribed text is typed directly into the currently focused app
- **Floating Capsule UI** — Dark glassmorphism overlay with live waveform visualization and transcript preview
- **BYOK (Bring Your Own Key)** — You provide your own API keys; credentials stay on your device in Keychain
- **Local VAD** — Silero Voice Activity Detection runs locally via ONNX Runtime, no network needed

## Requirements

| Requirement | Version |
|-------------|---------|
| macOS | 14.0 (Sonoma) or later |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Hardware | Apple Silicon (M1/M2/M3) or Intel Mac |

## Quick Install (DMG)

Download the latest `.dmg` from [GitHub Releases](https://github.com/axzml/VoxLinkAI_Client/releases), open it, and drag VoxLink AI to Applications.

> **macOS Gatekeeper notice:** The app is not notarized with Apple. On first launch, macOS may block it with "cannot be opened because the developer cannot be verified." To open it:
> 1. Right-click (or Control-click) the app in Applications
> 2. Select **Open** from the context menu
> 3. Click **Open** in the dialog
>
> You only need to do this once. Alternatively, run: `xattr -cr /Applications/VoxLinkAI.app`

After launch, open **Settings** and enter your Aliyun API Key. That's it.

## Build from Source

### 1. Clone the Repository

```bash
git clone https://github.com/axzml/VoxLinkAI_Client.git
cd VoxLinkAI
```

### 2. Configure Secrets

Copy the example configuration file and edit it:

```bash
cp VoxLinkAI/VoxLinkAI/Resources/Secrets.example.plist \
   VoxLinkAI/VoxLinkAI/Resources/Secrets.plist
```

The example file has `USE_MOCK_AUTH` set to `true` by default, so you can build and run immediately without Supabase.

Open `Secrets.plist` to review the configuration:

| Key | Description | Default |
|-----|-------------|---------|
| `USE_MOCK_AUTH` | Skip Supabase login (BYOK mode) | `true` |
| `SUPABASE_URL` | Your Supabase project URL | placeholder |
| `SUPABASE_ANON_KEY` | Your Supabase anon key | placeholder |
| `API_BASE_URL` | Your backend API base URL (optional) | empty |
| `WEBSITE_BASE_URL` | Your website base URL (optional) | empty |

> **Most users only need to:** keep `USE_MOCK_AUTH` as `true`, then add your Aliyun API Key in the app's Settings after launch. No backend server required.

### 3. Add Secrets.plist to Xcode

The file must be registered in the Xcode project to be included in the app bundle:

1. Open `VoxLinkAI.xcodeproj` in Xcode
2. In the Project Navigator, right-click the **Resources** folder
3. Select **Add Files to "VoxLinkAI"**
4. Choose `Secrets.plist`
5. Ensure **Target Membership** is checked for VoxLinkAI

### 4. Set Your Development Team

Since the project ships without a signing identity:

1. Select the **VoxLinkAI** target in Xcode
2. Go to **Signing & Capabilities**
3. Choose your **Team** from the dropdown
4. Xcode will handle provisioning automatically

### 5. Build and Run

Press `Cmd + R` in Xcode.

#### Keychain Prompt (Expected)

On first build, macOS will show a dialog asking for your system password to access the Keychain. **This is normal** — it happens because Xcode-signed development builds need to store credentials (API keys) in the macOS Keychain. Click **"Always Allow"** to avoid being prompted on every launch. Release builds with stable code signing won't have this issue.

#### Permission Prompts

After launch, macOS will ask you to grant:

| Permission | Why It's Needed |
|------------|-----------------|
| **Accessibility** | Global hotkey monitoring and text input to other apps |
| **Microphone** | Voice recording |

#### Accessibility Permission — Important First-Time Setup

On a fresh build, you may find the hotkey (Option) does not work even after enabling Accessibility for VoxLinkAI in System Settings. The app log will show:

```
[HotkeyManager] Accessibility permissions not granted, will retry...
```

This is a known macOS behavior with development-signed apps. To fix it:

1. Reset the permission via Terminal:
   ```bash
   tccutil reset Accessibility com.voxlinkai.VoxLinkAI
   ```
2. Quit the app completely (`Cmd + Q` or kill the process)
3. Build and run again in Xcode (`Cmd + R`)
4. macOS will prompt for Accessibility permission again — grant it this time

> **Note:** If you try to remove VoxLinkAI manually from System Settings -> Accessibility, the minus button may be grayed out. The `tccutil` command above is the reliable way to reset it.

After this second authorization, the hotkey will work correctly. This only needs to be done once (unless you clean-build the project, which changes the code signature).

### 6. Configure API Keys

Open the app's **Settings** and enter your Aliyun API Key for speech recognition and AI polishing.

## Obtaining API Keys

### Aliyun API Key (Required for voice features)

This key powers both speech recognition (FunASR) and AI text polishing (Qwen):

1. Sign up at [Aliyun](https://www.aliyun.com/)
2. Go to [Alibaba Cloud Bailian Console](https://bailian.console.aliyun.com/)
3. Create an API Key
4. Enter it in the app's Settings page

### Supabase (Optional — for user authentication)

Only needed if you want login/account functionality. Most users can skip this by keeping `USE_MOCK_AUTH` set to `true`.

1. Create a project at [supabase.com](https://supabase.com/)
2. Go to **Project Settings -> API**
3. Copy the **Project URL** -> `SUPABASE_URL`
4. Copy the **anon public key** -> `SUPABASE_ANON_KEY`
5. Paste them into your `Secrets.plist` and set `USE_MOCK_AUTH` to `false`

### Backend Server (Optional)

If you want to run your own backend for features like feedback submission and update checking:

1. Set `API_BASE_URL` in `Secrets.plist` to your backend URL
2. Set `WEBSITE_BASE_URL` to your website URL (used for legal pages, download links, etc.)
3. Without these, the app still works fully for voice input — feedback and update features will simply be disabled

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Option` (hold) | Start recording; release to finish and send |
| `Escape` | Cancel current recording |

The hotkey can be changed in Settings (Option, Control, Command, Shift, or Fn).

## Architecture

```
VoxLinkAI/
├── App/                    # App entry point & lifecycle
├── Core/
│   ├── ASR/               # Speech recognition (Aliyun FunASR, WebSocket)
│   ├── AI/                # AI text polishing (Aliyun Qwen, OpenAI-compatible)
│   ├── VAD/               # Voice Activity Detection (Silero, local ONNX)
│   ├── Auth/              # Authentication (Supabase)
│   ├── Hotkey/            # Global hotkey via CGEventTap
│   ├── Typing/            # Text input to other apps via Accessibility API
│   └── Services/          # Shared services
├── UI/
│   ├── Overlay/           # Floating capsule with waveform
│   ├── MenuBar/           # Menu bar integration
│   ├── Settings/          # Settings window
│   └── ...                # Other UI modules
├── Storage/               # Keychain, UserDefaults, SQLite
├── Models/                # Data models
└── Resources/
    ├── Secrets.example.plist   # Configuration template
    ├── silero_vad.onnx         # VAD model (bundled)
    └── Legal/                  # Privacy policy & terms
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI + AppKit |
| Speech Recognition | Aliyun FunASR (WebSocket) |
| AI Polishing | Aliyun Qwen (OpenAI-compatible API) |
| Voice Activity Detection | Silero VAD (ONNX Runtime, local) |
| Authentication | Supabase (optional) |
| Credential Storage | macOS Keychain |
| Local Data | SQLite + UserDefaults |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Hotkey not working after granting Accessibility | Run `tccutil reset Accessibility com.voxlinkai.VoxLinkAI`, quit, rebuild, and re-authorize. See [Accessibility Permission](#accessibility-permission--important-first-time-setup) above. |
| Cannot remove VoxLinkAI from Accessibility list (minus button grayed out) | Use the `tccutil` command above instead of the UI. |
| Keychain password prompt on every launch | Click "Always Allow" when prompted. This is a development build behavior, not a security concern. |
| Build error about missing `Secrets.plist` | Follow [Step 2](#2-configure-secrets) and [Step 3](#3-add-secretsplist-to-xcode) above. |
| Speech recognition not working | Ensure your Aliyun API Key is entered in Settings and your network can reach Aliyun services. |

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for our security policy and how to report vulnerabilities.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
