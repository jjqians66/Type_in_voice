# Type in Voice

Type in Voice is a lightweight desktop dictation app for people who think faster than they type. Press one shortcut, speak naturally, press it again, and the transcription appears in the text field you were using.

It is designed for mixed Chinese/English speech, technical vocabulary, and those small moments where switching apps breaks your flow.

## Download

Go to the **[latest Type in Voice release](https://github.com/jjqians66/Type_in_voice/releases/latest)** and download the file for your computer:

| Platform | Download | Install |
| --- | --- | --- |
| macOS 14+ (Apple silicon or Intel) | `TypeInVoice-macOS-universal.dmg` | Open the DMG and drag `TypeInVoice` to Applications. |
| Windows 10/11 (64-bit) | `TypeInVoice-Windows-x64-Setup.exe` | Open the installer and follow the short setup wizard. |

The current downloads are unsigned, so your computer may show a first-launch warning:

- **macOS:** Control-click TypeInVoice in Applications, choose **Open**, then **Open** again. If macOS still blocks it, open **System Settings → Privacy & Security** and click **Open Anyway**.
- **Windows:** in Microsoft Defender SmartScreen, click **More info → Run anyway**.

You do not need Xcode, Homebrew, .NET, or the source code to use either download.

## What it does

- **Dictate almost anywhere** — use `⌥D` on macOS or `Ctrl+Alt+D` on Windows.
- **Keeps your context** — remembers the window that had focus when recording started, then pastes there after transcription.
- **Mixed-language friendly** — auto-detect Chinese and English, or choose a language when you want a stronger hint.
- **Clear feedback** — shows a lightweight recording/transcription overlay without taking keyboard focus.
- **Safe fallback** — if automatic paste is unavailable, the result stays on your clipboard for a manual paste.
- **Secure credential storage** — stores your OpenAI API key in macOS Keychain or encrypted with Windows DPAPI.
- **Optional macOS cleanup** — can use GPT-4o-mini to improve punctuation and readability while preserving language and meaning.

## First-time setup

You need an OpenAI API key with access to the audio transcription API. Audio is sent directly from the app to OpenAI when you stop recording.

### macOS

1. Launch Type in Voice and find its waveform icon in the menu bar.
2. Open **Settings**, or press `⌥S`.
3. Paste your OpenAI API key and click **Save**.
4. Allow microphone access when prompted.
5. For automatic paste, grant Type in Voice access in **System Settings → Privacy & Security → Accessibility**.
6. Click a text field, press `⌥D`, speak, and press `⌥D` again.

### Windows

1. Launch Type in Voice. Settings open automatically the first time; afterward, double-click the tray icon or press `Ctrl+Alt+S`.
2. Paste your OpenAI API key, choose a language, and click **Save settings**.
3. Click a text field, press `Ctrl+Alt+D`, speak, and press `Ctrl+Alt+D` again.
4. If Windows prevents automatic paste into a particular app, the transcription remains on your clipboard; press `Ctrl+V`.

## Shortcuts

| Platform | Dictate / stop / cancel | Open settings |
| --- | --- | --- |
| macOS | `⌥D` | `⌥S` |
| Windows | `Ctrl+Alt+D` | `Ctrl+Alt+S` |

Press the dictation shortcut while Type in Voice is transcribing to cancel the current request. Recordings stop automatically after five minutes.

## Privacy

Type in Voice does not run analytics or maintain a local transcription database. The audio is sent to OpenAI's transcription endpoint after recording. On macOS, enabling the optional readability setting also sends the resulting text to OpenAI's chat completions endpoint.

The API key is stored locally: in macOS Keychain on Mac, and encrypted for the current Windows account with DPAPI on Windows. Transcribed text is placed on the system clipboard so it can be pasted into the captured target app. Review OpenAI's terms and privacy policy before dictating sensitive information.

## Troubleshooting

**The shortcut does nothing**

- Make sure Type in Voice is running in the macOS menu bar or Windows system tray.
- Check that an API key is saved in Settings.
- Another app may already own the shortcut. Use the tray/menu-bar command or temporarily disable the conflict.
- On macOS, confirm Microphone and Accessibility permissions in System Settings.

**The text was copied but not inserted**

Paste manually with `⌘V` on macOS or `Ctrl+V` on Windows. Type in Voice deliberately avoids pasting into an uncertain foreground window.

**The microphone is unavailable**

Allow microphone access in macOS System Settings or Windows **Settings → Privacy & security → Microphone**, then quit and reopen Type in Voice.

**My computer says the app is from an unknown publisher/developer**

The downloads are currently unsigned. Follow the one-time override steps in [Download](#download). Only download installers from this repository's Releases page.

## Development

### macOS

Requirements: macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/jjqians66/Type_in_voice.git
cd Type_in_voice
xcodegen generate
./script/build_and_run.sh --verify
```

The Xcode project is generated from `project.yml`; do not edit the generated project by hand. To create a local universal DMG and ZIP, run `./script/package_macos.sh`.

### Windows

Requirements: Windows 10/11 and the .NET 8 SDK. Inno Setup 6 is additionally required to create the installer.

```powershell
dotnet build windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj
dotnet run --project windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj
```

See [DISTRIBUTION.md](DISTRIBUTION.md) for the release workflow and [TEST_PLAN.md](TEST_PLAN.md) for cross-platform verification.

## Architecture

```text
global hotkey → microphone recording → PCM16 WAV → OpenAI transcription
             → clipboard → paste into the originally captured window
```

The macOS client is written in Swift/SwiftUI. The Windows client is a native WPF tray app distributed as a self-contained single-file executable, so end users do not need to install .NET.

## License

MIT License. See [LICENSE](LICENSE).
