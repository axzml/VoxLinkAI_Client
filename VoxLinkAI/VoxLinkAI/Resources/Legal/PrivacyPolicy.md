# VoxLink AI Privacy Policy / 隐私政策

**Last Updated / 最后更新:** March 2026

---

> **TL;DR — We Don't Have Servers / 简而言之 — 我们没有服务器**
>
> VoxLink AI is a local-first application. We operate **zero servers**. In BYOK mode, your voice data connects directly to Aliyun for transcription — it never passes through us.
>
> VoxLink AI 是一款本地优先的应用程序。我们运营**零台服务器**。在 BYOK 模式下，您的语音数据直接连接到阿里云进行转录 — 永远不会经过我们。

---

## English Version

### 1. Introduction

VoxLink AI ("we," "our," or "the App") is a free, open-source macOS voice input assistant released under the MIT License. This Privacy Policy explains how our App handles information when you use it.

**Core Principle:** We are a local-first application with zero server infrastructure. By default, we collect no data whatsoever.

### 2. Zero Data Collection Model

#### 2.1 BYOK Mode (Default)

When using the App in BYOK (Bring Your Own Key) mode:

- We collect **zero personal data**
- No user accounts are required
- No analytics or tracking
- Your Aliyun API key is stored locally in macOS Keychain — we cannot access it

#### 2.2 What Stays On Your Device

- Your Aliyun API key (stored in macOS Keychain)
- App preferences and settings
- Transcription history (if enabled, stored in local SQLite database)
- Hotkey configurations

### 3. Voice Data Processing

#### 3.1 How Voice Data Flows

| Step | Process | Network Required? |
|------|---------|-------------------|
| 1 | Voice Activity Detection | **No** — Silero VAD runs locally via ONNX Runtime |
| 2 | Audio Capture | No — Local microphone |
| 3 | Transcription | **Yes** — Direct to Aliyun FunASR |
| 4 | AI Polishing | **Yes** — Direct to Aliyun Qwen |
| 5 | Text Output | No — Local auto-typing |

**Key Point:** Your voice data never passes through our servers because **we don't have any servers**.

#### 3.2 Audio Retention

- Original audio is **not stored** after transcription
- Transcribed text may be stored locally in your transcription history (you can disable this in Settings)
- We have no access to any of your data

### 4. API Key Management

- **Local Storage Only:** Your Aliyun API key is stored exclusively in macOS Keychain
- **Encrypted:** Keys are encrypted using system-level security
- **Zero Access:** We cannot access your API keys
- **Your Responsibility:** You are responsible for managing your API key and monitoring your Aliyun usage

### 5. Third-Party Services

| Service | Purpose | Required? | Privacy Policy |
|---------|---------|-----------|----------------|
| [Aliyun FunASR](https://www.alibabacloud.com/) | Speech recognition | Yes* | [View](https://www.alibabacloud.com/help/doc-detail/42321.htm) |
| [Aliyun Qwen](https://tongyi.aliyun.com/) | AI text polishing | Yes** | [View](https://www.alibabacloud.com/help/doc-detail/42321.htm) |
| [Supabase](https://supabase.com/) | Optional authentication | No | [View](https://supabase.com/privacy) |

\* Required for speech-to-text functionality
\** Required for AI text polishing (can be disabled in Settings)

### 6. Permissions Requested

| Permission | Why It's Needed |
|------------|-----------------|
| **Microphone** | To capture your voice for transcription |
| **Accessibility** | To monitor global hotkeys and type text into other applications |

Both permissions are requested only when you first use the relevant feature.

### 7. Optional Cloud Authentication

If you choose to enable Supabase authentication (completely optional):

- We collect your **email address** for account identification
- We store **usage quota data** for cross-device syncing
- You can delete your account at any time from App Settings

**All core features work without authentication.**

### 8. Data Security

- **Local Encryption:** API keys encrypted using macOS Keychain
- **Transit Encryption:** All network communications use HTTPS/TLS
- **Local-First:** Sensitive data never leaves your device except when directly transmitted to Aliyun

### 9. Your Rights

- **Full Control:** All local data is under your complete control
- **No Account Required:** Use all core features without creating an account
- **Export:** Export your local data at any time via Settings
- **Delete:** Clear all local data or delete your optional cloud account

### 10. Children's Privacy

This App is not directed at children under 13. We do not knowingly collect personal information from children under 13. If you are a parent and believe your child has provided us with personal information, please contact us.

### 11. Changes to This Policy

We may update this Privacy Policy from time to time. We will notify users of any material changes through:

- The App's Settings page
- Our GitHub repository

### 12. Contact Us

If you have questions about this Privacy Policy, please contact:

**Email:** support@voxlinkai.com
**GitHub:** https://github.com/axzml/VoxLinkAI_Client

---

## 中文版

### 1. 简介

VoxLink AI 是一款免费、开源的 macOS 语音输入助手，采用 MIT 许可证发布。本隐私政策说明了您使用我们的应用程序时我们如何处理信息。

**核心原则：** 我们是本地优先的应用程序，没有服务器基础设施。默认情况下，我们根本不收集任何数据。

### 2. 零数据收集模式

#### 2.1 BYOK 模式（默认）

在 BYOK（自带密钥）模式下使用应用程序时：

- 我们收集**零个人数据**
- 无需用户账户
- 无分析或跟踪
- 您的阿里云 API 密钥存储在本地 macOS Keychain 中 — 我们无法访问它

#### 2.2 保留在您设备上的数据

- 您的阿里云 API 密钥（存储在 macOS Keychain 中）
- 应用偏好设置
- 转录历史（如启用，存储在本地 SQLite 数据库中）
- 快捷键配置

### 3. 语音数据处理

#### 3.1 语音数据如何流转

| 步骤 | 处理过程 | 需要网络？ |
|------|----------|------------|
| 1 | 语音活动检测 | **否** — Silero VAD 通过 ONNX Runtime 本地运行 |
| 2 | 音频捕获 | 否 — 本地麦克风 |
| 3 | 转录 | **是** — 直连阿里云 FunASR |
| 4 | AI 润色 | **是** — 直连阿里云 Qwen |
| 5 | 文本输出 | 否 — 本地自动输入 |

**关键点：** 您的语音数据永远不会通过我们的服务器，因为**我们没有任何服务器**。

#### 3.2 音频保留

- 原始音频在转录后**不存储**
- 转录文本可能存储在本地转录历史中（可在设置中禁用）
- 我们无法访问您的任何数据

### 4. API 密钥管理

- **仅本地存储：** 您的阿里云 API 密钥仅存储在 macOS Keychain 中
- **加密：** 密钥使用系统级安全加密
- **零访问：** 我们无法访问您的 API 密钥
- **您的责任：** 您负责管理您的 API 密钥并监控您的阿里云使用情况

### 5. 第三方服务

| 服务 | 用途 | 必需？ | 隐私政策 |
|------|------|--------|----------|
| [阿里云 FunASR](https://www.aliyun.com/) | 语音识别 | 是* | [查看](https://terms.alicdn.com/legal-agreement/terms/suit_bu1_alibaba_group/suit_bu1_alibaba_group202107141244_48204.html) |
| [阿里云 Qwen](https://tongyi.aliyun.com/) | AI 文本润色 | 是** | [查看](https://terms.alicdn.com/legal-agreement/terms/suit_bu1_alibaba_group/suit_bu1_alibaba_group202107141244_48204.html) |
| [Supabase](https://supabase.com/) | 可选认证 | 否 | [查看](https://supabase.com/privacy) |

\* 语音转文字功能所必需
\** AI 文本润色功能所必需（可在设置中禁用）

### 6. 所需权限

| 权限 | 为什么需要 |
|------|------------|
| **麦克风** | 捕获您的语音进行转录 |
| **辅助功能** | 监听全局快捷键并将文本输入到其他应用程序 |

两项权限仅在您首次使用相关功能时请求。

### 7. 可选云认证

如果您选择启用 Supabase 认证（完全可选）：

- 我们收集您的**邮箱地址**用于账户识别
- 我们存储**用量配额数据**用于跨设备同步
- 您可以随时从应用设置中删除账户

**所有核心功能无需认证即可使用。**

### 8. 数据安全

- **本地加密：** API 密钥使用 macOS Keychain 加密
- **传输加密：** 所有网络通信使用 HTTPS/TLS
- **本地优先：** 敏感数据永不离开您的设备，除非直接传输到阿里云

### 9. 您的权利

- **完全控制：** 所有本地数据由您完全控制
- **无需账户：** 无需创建账户即可使用所有核心功能
- **导出：** 随时通过设置导出本地数据
- **删除：** 清除所有本地数据或删除可选的云账户

### 10. 儿童隐私

本应用不面向 13 岁以下儿童。我们不会故意收集 13 岁以下儿童的个人身份信息。如果您是家长并认为您的孩子向我们提供了个人身份信息，请联系我们。

### 11. 政策变更

我们可能会不时更新本隐私政策。我们将通过以下方式通知用户任何重大变更：

- 应用的设置页面
- 我们的 GitHub 仓库

### 12. 联系我们

如果您对本隐私政策有任何疑问，请联系：

**邮箱：** support@voxlinkai.com
**GitHub：** https://github.com/axzml/VoxLinkAI_Client
