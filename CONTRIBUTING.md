# 贡献指南

感谢您对 VoxLink AI 的关注！我们欢迎任何形式的贡献，包括但不限于：

- 🐛 报告 Bug
- 💡 提出新功能建议
- 📝 完善文档
- 💻 提交代码改进
- 🌐 翻译文档

## 行为准则

请阅读并遵守我们的 [行为准则](CODE_OF_CONDUCT.md)（如有）。我们期望所有贡献者都能保持友好和尊重。

## 如何贡献

### 1. 报告 Bug

如果您发现了 Bug，请：

1. 搜索现有 [Issues](https://github.com/axzml/VoxLinkAI_Client/issues) 是否已报告
2. 如未报告，创建新的 Issue，包含：
   - 清晰的标题和描述
   - 复现步骤
   - 预期行为 vs 实际行为
   - 您的系统环境（macOS 版本等）

### 2. 提出新功能

我们欢迎功能建议！请：

1. 搜索现有 Issues 和 Discussions
2. 清晰描述您的想法
3. 说明为什么这个功能有用
4. 如有可能，提供伪代码或设计草图

### 3. 提交代码

#### 开发环境

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

#### 步骤

1. **Fork** 本仓库
2. **Clone** 您的 Fork：
   ```bash
   git clone https://github.com/YOUR_USERNAME/VoxLinkAI_Client.git
   ```
3. **创建** 分支：
   ```bash
   git checkout -b feature/your-feature-name
   # 或
   git checkout -b fix/bug-description
   ```
4. **开发** 您的改动
5. **测试** 确保代码正常工作
6. **提交** 您的改动：
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```
7. **Push** 到您的 Fork：
   ```bash
   git push origin feature/your-feature-name
   ```
8. **创建** Pull Request

#### Pull Request 指南

- 保持 PR 简洁，专注于单一功能或修复
- 填写 PR 模板，提供清晰的描述
- 确保代码符合项目现有的风格
- 添加必要的测试（如适用）
- 更新文档（如有必要）

### 代码风格

本项目使用标准的 Swift 代码风格：

- 使用 SwiftLint（如果配置）
- 遵循 Apple 的 [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- 使用有意义的变量和函数命名
- 添加适当的注释和文档注释

### 提交信息格式

推荐使用 [Conventional Commits](https://www.conventionalcommits.org/) 格式：

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

类型 (type) 包括：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式调整
- `refactor`: 代码重构
- `test`: 测试相关
- `chore`: 构建或辅助工具改动

示例：
```
feat(ASR): add support for new audio format

fix(auth): resolve token refresh issue on macOS 14
```

## 财务贡献

VoxLink AI 是一个免费开源项目。如果您愿意支持开发，可以：

- 在 GitHub 上 star 本项目
- 分享给需要的朋友
- 提交代码贡献

## 联系方式

- 问题讨论：[GitHub Discussions](https://github.com/axzml/VoxLinkAI_Client/discussions)
- Bug 报告：[GitHub Issues](https://github.com/axzml/VoxLinkAI_Client/issues)

---

感谢您的贡献！🎉
