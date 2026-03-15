# VoxLink AI 配置说明

## 快速开始（无需配置 Supabase）

默认情况下，`Secrets.example.plist` 中 `USE_MOCK_AUTH` 为 `true`，这意味着：

1. **无需配置 Supabase** 即可编译和运行
2. 应用会跳过登录界面，直接进入主窗口
3. 用户需要自己在设置中填入阿里云 API Key（BYOK 模式）

```bash
# 只需复制配置文件即可开始开发
cd VoxLinkAI
cp VoxLinkAI/Resources/Secrets.example.plist VoxLinkAI/Resources/Secrets.plist
```

然后在 Xcode 中添加 `Secrets.plist` 到项目即可。

---

## 启用用户登录功能（可选）

如果你需要用户登录和配额管理功能，需要配置 Supabase：

### 1. 修改 Secrets.plist

将 `USE_MOCK_AUTH` 改为 `false`，并填入 Supabase 配置：

```xml
<key>SUPABASE_URL</key>
<string>https://你的项目ID.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>你的 anon key</string>
<key>USE_MOCK_AUTH</key>
<false/>
```

### 2. 从 Supabase 获取凭据

1. 登录 [Supabase Dashboard](https://supabase.com/dashboard)
2. 创建新项目或选择已有项目
3. 进入 **Project Settings → API**
4. 复制：
   - **Project URL** → `SUPABASE_URL`
   - **anon public key** → `SUPABASE_ANON_KEY`

---

## 配置文件添加步骤

文件存在于文件夹不等于它被项目包含。你需要：

1. 打开 Xcode
2. 在左侧项目导航器中，右键点击 `Resources` 文件夹
3. 选择 **Add Files to "VoxLinkAI"**
4. 选择 `Secrets.plist`
5. 勾选 **Copy items if needed**（如果提示的话）
6. 确保 **Target Membership** 勾选了 VoxLinkAI

---

## 阿里云 API Key（必需）

无论是否启用 Supabase 登录，都需要配置阿里云 API Key：

1. 注册 [阿里云账号](https://www.aliyun.com/)
2. 开通 [FunASR](https://help.aliyun.com/document_detail/261197.html) 服务
3. 获取 API Key：[阿里云百炼控制台](https://bailian.console.aliyun.com/)
4. 在应用设置中填入 API Key

---

## 安全注意事项

⚠️ **永远不要将以下文件提交到 Git：**

- `VoxLinkAI/Resources/Secrets.plist`

此文件已在 `.gitignore` 中排除。

---

## 验证配置

在 Xcode 中运行项目，如果配置正确：
- `USE_MOCK_AUTH=true`（默认）→ 直接进入应用（BYOK 模式）
- `USE_MOCK_AUTH=false` + Supabase 配置 → 显示登录界面
- API Key 未配置 → 会在设置页面提示
