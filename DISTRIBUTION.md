# Releasing Type in Voice

Type in Voice ships as a macOS DMG/ZIP and a self-contained Windows installer. End users do not need Xcode, Homebrew, .NET, or a source checkout.

## Create a public release

1. Update the version in `project.yml`, `windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj`, and `windows/installer/TypeInVoice.iss`.
2. Run the checks in `TEST_PLAN.md`.
3. Push a matching version tag:

   ```bash
   git tag v2.1.0
   git push origin v2.1.0
   ```

The **Build release installers** GitHub Actions workflow builds both operating systems and attaches these files to a new GitHub Release:

- `TypeInVoice-macOS-universal.dmg`
- `TypeInVoice-macOS-universal.zip`
- `TypeInVoice-Windows-x64-Setup.exe`
- `SHA256SUMS.txt`

You can also run the workflow manually to test its build jobs. Manual runs create downloadable workflow artifacts but do not publish a GitHub Release.

## Unsigned-app warnings

The public builds are intentionally unsigned for now. Users can still run them:

- **macOS:** drag the app to Applications, Control-click it, choose **Open**, then choose **Open** again. If needed, use **System Settings → Privacy & Security → Open Anyway**.
- **Windows:** start the installer, choose **More info**, then **Run anyway** in Microsoft Defender SmartScreen.

Code signing can be added later without changing the app or installer format. Never commit signing certificates, private keys, or API keys to this repository.

## Local macOS package

```bash
./script/package_macos.sh
```

The script writes the DMG and ZIP to `dist/`.

## Local Windows package

On Windows with .NET 8 and Inno Setup 6 installed:

```powershell
dotnet publish windows/TypeInVoice.Windows/TypeInVoice.Windows.csproj --configuration Release --runtime win-x64 --self-contained true
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" windows\installer\TypeInVoice.iss
```
