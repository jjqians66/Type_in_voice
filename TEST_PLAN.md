# Type in Voice Test Plan

这个测试计划覆盖 macOS 菜单栏版和 Windows 托盘版 Type in Voice。它把真正可自动化的检查、需要人工授权的系统权限检查、以及 Playwright 的适用边界分开，避免把浏览器 E2E 工具误用到原生桌面 App 上。

## 1. Build and Launch Smoke Test

目标：确认 Xcode 构建产物稳定、启动路径固定、不会残留多个后台实例争抢快捷键。

命令：

```sh
./script/build_and_run.sh --verify
pgrep -x TypeInVoice | wc -l
```

通过标准：

- `xcodebuild` 成功。
- 脚本使用的 Derived Data 目录中存在 `Build/Products/Debug/TypeInVoice.app`（默认在系统临时目录，可用 `TYPE_IN_VOICE_DERIVED_DATA` 覆盖）。
- `TypeInVoice` 进程正在运行。
- `pgrep -x TypeInVoice | wc -l` 输出 `1`。

必要性：

- 用户从 Xcode/DerivedData 反复启动时，最容易产生多个后台实例，导致 `Option+D` 有时无响应、有时被多个实例同时处理。
- 固定构建和启动路径后，排查权限和快捷键问题才有稳定基线。

## 2. Install and Login Item Test

目标：确认这不是只能在 Xcode 里跑的开发态 App，而是开机后可直接使用。

命令：

```sh
./script/install_app.sh
```

手动步骤：

1. 打开菜单栏中的 Type in Voice。
2. 按 `Option+S` 打开设置。
3. 开启 `Launch at Login`。
4. 在系统设置里授予 `/Applications/TypeInVoice.app` 麦克风和辅助功能权限。
5. 退出登录再登录，或重启 Mac，确认菜单栏图标自动出现。

通过标准：

- `/Applications/TypeInVoice.app` 存在并能启动。
- 登录后菜单栏图标出现。
- `Option+D` 可以开始录音，再按一次可以停止。

必要性：

- Xcode 构建出来的 App 位于 DerivedData，路径会变化；macOS 的麦克风/辅助功能权限绑定到 App 路径和签名状态，路径变化会造成“昨天能用、今天又不行”。
- 安装到 `/Applications` 后，权限和登录项都指向稳定位置。

## 3. Hotkey State Machine Test

目标：验证 `Option+D` 在各状态下只有一个明确动作。

测试矩阵：

| 初始状态 | 操作 | 预期 |
| --- | --- | --- |
| Idle | 按 `Option+D` | 进入 Recording |
| Recording | 再按 `Option+D` | 停止录音并进入 Processing |
| Processing | 再按 `Option+D` | 取消当前转写并回到 Idle |
| Connecting | 再按 `Option+D` | 取消当前操作并回到 Idle |
| 任意状态 | 快速重复按键 | 0.45 秒内重复事件被忽略 |

可辅助命令：

```sh
osascript -e 'tell application "System Events" to key code 2 using option down'
```

通过标准：

- 不会因为按键重复触发而启动两段录音。
- 转写中再次按 `Option+D` 可以取消，不会卡在“过不去/不停止”的状态。

必要性：

- 之前 `.processing` 状态忽略快捷键，网络慢或 API 卡住时用户没有办法用同一个快捷键中断。
- 没有按键防抖时，系统 key repeat 或多个实例会放大成重复录音/重复粘贴。

## 4. Paste Backend Test

目标：验证文本插入只发生一次，并且发给录音开始时捕获的目标 App。

手动流程：

1. 打开 TextEdit，新建纯文本窗口。
2. 确认光标在 TextEdit 文档中。
3. 按 `Option+D` 开始录音，说一句短句。
4. 再按 `Option+D` 停止。
5. 等待转写完成并自动粘贴。

通过标准：

- TextEdit 中只出现一次最终结果。
- 不应该粘贴到 Type in Voice 设置窗口、菜单栏弹窗、或其他后来获得焦点的 App。
- 如果没有辅助功能权限，结果应保留在剪贴板，并显示需要授权的错误状态。

建议增加的自动化脚本：

```sh
swift test_postToPid.swift
```

当前 `test_postToPid.swift` 只是确认 frontmost app PID。后续可以扩展成串行测试：打开 TextEdit、写入唯一 token 到剪贴板、对捕获 PID 发送 paste 事件、断言 token 只出现一次。

必要性：

- 重复粘贴通常不是转写本身的问题，而是事件发送目标、多个实例、或重复热键导致的副作用。
- 捕获录音开始时的目标 PID 可以避免菜单弹窗/设置窗口改变焦点后粘贴到错误位置。

## 5. Transcription Backend Test

目标：分开验证录音、API 调用、粘贴，不把所有失败都归因到快捷键。

Mock 测试：

- 给 `TranscriptionService` 增加协议抽象或测试替身。
- 用固定返回值验证 `AppState` 在 success、empty result、network error、cancelled 四种情况下的状态迁移。
- 断言 success 只调用一次 `TextInserter.insertText`。

真实 API 测试：

1. 使用有效 OpenAI API key。
2. 录一段 2 到 3 秒的短句。
3. 观察日志中只出现一次完成事件。
4. 断言 UI 回到 Idle。

通过标准：

- API 成功时状态回到 Idle，并尝试插入一次。
- API 失败时显示错误，不清空用户可恢复的剪贴板内容。
- 用户在 Processing 时按 `Option+D`，请求被取消并回到 Idle。

必要性：

- 真实网络会慢、失败、或超时；状态机必须能恢复。
- 用 mock 测试可以避免 CI 或本地回归依赖真实 OpenAI 调用。

## 6. Playwright Coverage

Playwright 适合：

- 如果后续增加本地 Web debug harness，例如显示 AppState 状态、模拟 transcription response、或展示 API 设置页，可以用 Playwright 跑浏览器 E2E。
- 如果后端服务拆成 HTTP API，可以用 Playwright/APIRequestContext 或普通 HTTP 测试覆盖请求和响应。

Playwright 不适合：

- 直接点击 macOS 菜单栏图标。
- 直接授予系统麦克风/辅助功能权限。
- 直接验证全局热键是否被原生 App 接收。
- 直接验证 CGEvent 是否粘贴到了 TextEdit。

当前建议：

- 原生 App E2E 使用 `xcodebuild`、`osascript`、`pgrep`、日志断言、以及受控 TextEdit 测试。
- Playwright 作为 backend/debug harness 的 backup，而不是替代 macOS 原生自动化。

必要性：

- 使用错误工具会产生假的 E2E 覆盖：测试绿了，但真实菜单栏、权限、全局快捷键、粘贴链路仍可能坏。
- 明确工具边界后，测试结果才可信。

## 7. Windows Build and Install Test

目标：确认 Windows 客户端可编译、最终安装包不要求用户预装 .NET，并且卸载路径完整。

CI / Windows 命令：

```powershell
dotnet build windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj --configuration Release
dotnet publish windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj --configuration Release --runtime win-x64 --self-contained true
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" windows\installer\TypeInVoice.iss
```

手动步骤：

1. 在一台没有安装 .NET SDK/runtime 的 64-bit Windows 10/11 机器运行 `TypeInVoice-Windows-x64-Setup.exe`。
2. SmartScreen 出现时点击 **More info → Run anyway**。
3. 确认首次打开自动显示设置窗口，保存 API key 后退出并重开仍能读取。
4. 在 Notepad 中按 `Ctrl+Alt+D` 录音，再按一次停止，确认只粘贴一次。
5. 转写中再按一次快捷键，确认可取消。
6. 让目标窗口在转写完成前退出，确认结果只留在剪贴板，没有粘贴到其他窗口。
7. 从 Windows Settings 的 Installed apps 卸载，确认程序和快捷方式被移除。

通过标准：

- 安装器无需管理员权限，普通用户可安装。
- 没有预装 .NET 的机器可以启动。
- API key 文件无法作为明文读取（使用当前 Windows 账户 DPAPI 加密）。
- 系统快捷键、托盘菜单、状态浮层、取消和剪贴板 fallback 均符合预期。

## 8. Release Artifact Test

在 GitHub Actions 手动运行 **Build release installers**，下载两个 workflow artifacts 并检查：

- macOS artifact 包含 universal DMG 和 ZIP；`lipo -info TypeInVoice.app/Contents/MacOS/TypeInVoice` 同时显示 `arm64`、`x86_64`。
- Windows artifact 包含 `TypeInVoice-Windows-x64-Setup.exe`。
- 两个安装包的名字与 README 下载表完全一致。
- 从 Releases 页面下载的产物能按 README 的一次性 override 指引启动。

## 9. Regression Checklist

每次改动后至少跑：

```sh
./script/build_and_run.sh --verify
pgrep -x TypeInVoice | wc -l
```

然后手动确认：

- `Option+S` 打开设置。
- `Option+D` 开始录音。
- 第二次 `Option+D` 停止录音。
- Processing 时再次 `Option+D` 可以取消。
- 最终文字只粘贴一次。
- 退出并重开后仍只有一个实例。
- Windows 上 `Ctrl+Alt+S` 打开设置，`Ctrl+Alt+D` 完成录音/停止/取消。
- Windows 安装机上没有 .NET runtime 也能启动。
