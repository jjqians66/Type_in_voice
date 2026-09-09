# Type in Voice：架构与实现说明

这份文档记录 Type in Voice 当前真实运行的架构。它提供原生 macOS 菜单栏版和 Windows 托盘版：用户在任意输入框里按下快捷键，说完后再次按下，应用把录音转成文字并安全地粘贴回录音开始时的目标窗口。

## 1. 产品目标

- 用一个全局快捷键完成开始、停止和取消，不打断当前工作流。
- 对中英文混说、技术术语和原文语气保持友好；默认不翻译、不回答语音里的问题。
- 让录音、转写、粘贴三个阶段都有明确反馈。
- 没有辅助功能权限时不丢文字：结果会保留在系统剪贴板中，用户可以手动 `⌘V`。
- 把 API key 放在 macOS Keychain 或 Windows 当前账户的 DPAPI 加密存储中，而不是源代码或明文配置文件里。

## 2. 数据流

```text
⌥D
  → 捕获当前前台 App 的 PID
  → AVAudioEngine 录音
  → 转成 24 kHz / 单声道 / PCM16 WAV
  → OpenAI transcription endpoint
  → 可选 GPT-4o-mini 标点与可读性处理
  → 写入剪贴板，并向原目标 PID 发送一次 ⌘V
```

当前实现是“录完再转写”的 REST 流程，不是 Realtime/WebSocket 流式转写。悬浮窗的波形是本地麦克风电平和 FFT 频段的可视化，不代表网络端已经返回了逐字结果。

Windows 版使用对应流程：`Ctrl+Alt+D → NAudio WaveInEvent → 24 kHz 单声道 PCM16 WAV → OpenAI → Windows Clipboard + SendInput(Ctrl+V)`。Windows 版的浮层目前显示阶段状态，不绘制 FFT 波形。

## 3. 模块职责

### `AppState.swift`

集中管理 `idle → connecting → recording → processing → idle` 状态机、快捷键行为、录音计时器、取消操作、错误状态和最终粘贴流程。单次录音最多五分钟，到时自动停止并提交转写。

### `AudioRecorder.swift`

通过 `AVAudioEngine` 采集麦克风，将系统输入格式转换为 24 kHz 单声道 PCM16；同时计算 RMS 电平和七个 FFT 频段，驱动悬浮窗动画。录音数据由锁保护，避免音频回调和主线程读取产生竞态。

### `TranscriptionService.swift`

使用 `URLSession` 发送 multipart WAV 请求到 OpenAI transcription endpoint。改名后使用 `com.typeinvoice.app` 的 Keychain 服务；首次读取时会从旧的 `com.whispertype.app` 服务迁移已有 key，升级不会要求用户重新配置。

### `TextInserter.swift`

先把结果放入系统剪贴板，再在 Accessibility 权限允许时向录音开始时保存的目标 PID 发送一次 `⌘V`。如果目标 App 已退出，Type in Voice 不会改粘到一个不确定的前台 App，而是把结果留在剪贴板。

### `WaveformOverlay.swift` / `OverlayWindowController.swift`

使用不会激活窗口的 `NSPanel` 显示录音状态、计时、波形和转写中提示。用户可以在 Settings 里关闭 overlay；关闭后录音流程仍然正常工作。

### `windows/TypeInVoice.Windows/`

WPF 托盘客户端。`DictationController` 管理 idle / recording / processing 状态；`AudioRecorderService` 使用 NAudio 录制 WAV；`TranscriptionService` 调用 OpenAI；`NativeMethods` 注册系统快捷键并只向录音开始时捕获的安全目标窗口发送一次 `Ctrl+V`。发布时会生成包含 .NET runtime 的单文件程序，最终由 Inno Setup 打成普通 Windows 安装包。

## 4. 关键交互决策

- `⌥D` 在录音中表示停止；在连接或转写中表示取消。这样网络慢时用户仍有明确的退出路径。
- 快捷键有 0.45 秒防抖，避免 key repeat 或快速重复触发造成双录音、双粘贴。
- 菜单栏菜单里的录音按钮与快捷键共享同一状态机，转写中也可以直接点“Cancel transcription”。
- 目标 App 只在录音开始时捕获，避免设置窗口或菜单栏 UI 改变焦点后发生误粘贴。
- 关闭 overlay 只是关闭视觉反馈，不会关闭录音、转写或自动粘贴。

## 5. 权限与隐私边界

- 麦克风权限用于录音。
- macOS Accessibility 权限只用于模拟 `⌘V`，没有该权限时仍然可以拿到剪贴板结果。Windows 通过系统窗口句柄与 `SendInput` 恢复目标并发送 `Ctrl+V`；目标不可确认时同样只保留剪贴板。
- 录音停止后，音频会发送到 OpenAI 做转写；开启可读性处理后，转写文本还会发送到 OpenAI 的 chat completions endpoint。
- 应用本身不维护本地数据库或 analytics 服务。剪贴板由 macOS 管理，用户应避免把敏感内容发送到未审核的第三方服务。

## 6. 本地验证

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

需要真实系统权限的回归流程见 [TEST_PLAN.md](TEST_PLAN.md)，尤其包括 TextEdit 单次粘贴、转写中取消、目标 App 退出、麦克风拒绝和无 Accessibility 权限等情况。

发布流程见 [DISTRIBUTION.md](DISTRIBUTION.md)。GitHub tag 会同时生成 macOS universal DMG/ZIP 和 Windows x64 安装包；当前产物不签名，首次启动按 README 的系统 override 指引处理。
