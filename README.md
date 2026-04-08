# VoiceInput

一款轻量级 macOS 菜单栏语音输入法应用，支持多语言语音识别，可将语音转换为文字并自动插入到任意应用的输入框中。

## 功能特性

- 🎤 **一键录音** - 点击菜单栏图标即可开始/停止录音
- 🔊 **实时语音识别** - 使用 Apple Speech 框架进行流式语音识别
- 🌍 **多语言支持** - 支持简体中文、繁体中文、英语、日语、韩语
- 📝 **自动文字插入** - 识别的文字自动插入到当前聚焦的输入框
- 🎨 **精美悬浮窗** - 胶囊式悬浮窗显示录音状态和实时文字
- 📊 **波形动画** - 实时音频波形可视化反馈
- 🤖 **LLM 文本优化** - 支持 OpenAI 兼容 API 进行文本纠错优化
- 🔒 **隐私优先** - 所有数据本地处理，语音识别使用 Apple 本地引擎

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon (M1/M2/M3) 或 Intel Mac

## 安装

### 方式一：下载 DMG（推荐）

1. 下载 `VoiceInput-1.0.0.dmg`
2. 双击打开 DMG 文件
3. 将 VoiceInput 拖拽到 Applications 文件夹
4. 从启动台或 Spotlight 启动 VoiceInput

### 方式二：从源码构建

```bash
# 克隆仓库
git clone https://github.com/yourusername/VoiceInput.git
cd VoiceInput

# 构建
make build

# 签名（需要开发环境）
make sign

# 安装到 Applications
make install
```

## 使用方法

### 基本操作

1. **启动应用** - 首次启动会请求麦克风和语音识别权限
2. **开始录音** - 点击菜单栏麦克风图标
3. **说话** - 对着麦克风说话，悬浮窗会实时显示识别的文字
4. **停止录音** - 再次点击菜单栏图标，文字会自动插入到当前输入框

### 菜单栏右键菜单

- **开始/停止录音** - 左键点击切换录音状态
- **语言选择** - 右键菜单选择识别语言
- **LLM 优化** - 启用/禁用文本优化，配置 API
- **关于/退出** - 其他选项

### 权限设置

应用需要以下权限：

1. **麦克风权限** - 用于录音
2. **语音识别权限** - 用于语音转文字
3. **辅助功能权限** - 用于将文字插入到其他应用

> ⚠️ 如果文字无法插入，请检查「系统设置」→「隐私与安全性」→「辅助功能」中是否已勾选 VoiceInput。

## LLM 文本优化

启用 LLM 优化后，识别的文字会经过 AI 处理，纠正语音识别错误（如中文同音字）。

### 配置步骤

1. 右键菜单栏图标 → LLM 优化 → LLM 设置
2. 填写配置：
   - **API 地址** - OpenAI 兼容 API 地址（如 `https://api.openai.com/v1`）
   - **API Key** - 你的 API 密钥
   - **模型** - 使用的模型名称（如 `gpt-4o-mini`）
3. 启用 LLM 优化

### 支持的 API

- OpenAI
- Azure OpenAI
- Claude (通过兼容接口)
- 本地模型 (Ollama, LM Studio 等)
- 其他 OpenAI 兼容 API

## 项目结构

```
VoiceInput/
├── Package.swift              # Swift Package Manager 配置
├── Makefile                   # 构建命令
├── Sources/VoiceInput/
│   ├── App.swift              # 应用入口
│   ├── Controllers/
│   │   ├── AppDelegate.swift  # 菜单栏、权限处理
│   │   └── VoiceInputController.swift  # 主控制器
│   ├── Models/
│   │   ├── Language.swift     # 语言枚举
│   │   ├── LLMConfig.swift    # LLM 配置
│   │   └── Settings.swift     # 设置存储
│   ├── Services/
│   │   ├── KeyEventMonitor.swift     # 键盘监听（备用）
│   │   ├── LLMRefiner.swift          # LLM API 客户端
│   │   ├── SpeechRecognizer.swift    # 语音识别
│   │   └── TextInjector.swift        # 文字注入
│   └── Views/
│       ├── FloatingPanel.swift       # 悬浮窗
│       ├── SettingsWindow.swift      # 设置窗口
│       └── WaveformView.swift        # 波形动画
├── Resources/
│   └── Info.plist             # 应用配置
└── Entitlements/
    └── VoiceInput.entitlements  # 权限声明
```

## 构建命令

```bash
# 完整构建（推荐）
make build

# 构建并签名
make sign

# 运行应用
make run

# 安装到 Applications
make install

# 创建 DMG 安装包
make dmg

# 清理构建文件
make clean
```

## 技术栈

- **语言**: Swift 5.9
- **UI 框架**: AppKit (Cocoa)
- **语音识别**: Apple Speech Framework
- **音频处理**: AVAudioEngine
- **文字注入**: NSAppleScript + Clipboard
- **设置存储**: UserDefaults
- **构建工具**: Swift Package Manager

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                        VoiceInput                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 用户点击菜单栏图标                                        │
│           ↓                                                 │
│  2. VoiceInputController 开始录音                           │
│           ↓                                                 │
│  3. SpeechRecognizer 捕获音频 → Apple Speech API            │
│           ↓                                                 │
│  4. 实时识别结果 → FloatingPanel 显示                        │
│           ↓                                                 │
│  5. 用户再次点击停止录音                                      │
│           ↓                                                 │
│  6. 等待最终识别结果                                         │
│           ↓                                                 │
│  7. (可选) LLMRefiner 优化文本                               │
│           ↓                                                 │
│  8. TextInjector 激活目标应用 → 剪贴板 → Cmd+V               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 常见问题

### Q: 文字无法插入到输入框？

检查以下项目：
1. VoiceInput 是否在「辅助功能」权限列表中
2. 录音时是否有文字显示在悬浮窗
3. 目标应用是否处于激活状态

### Q: 没有声音识别结果？

检查以下项目：
1. 麦克风权限是否已授权
2. 语音识别权限是否已授权
3. 是否选择了正确的语言

### Q: 如何添加自定义 LLM API？

1. 打开 LLM 设置
2. 输入 API 地址（如 `http://localhost:11434/v1` 用于 Ollama）
3. 如果不需要 API Key 可以留空
4. 输入模型名称

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 致谢

- Apple Speech Framework
- SwiftUI/AppKit
- 所有贡献者