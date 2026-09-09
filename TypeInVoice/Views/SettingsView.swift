import SwiftUI
import ServiceManagement

/// Settings window with General and Transcription tabs
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TranscriptionSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))

                Toggle("Show recording overlay", isOn: $appState.showOverlay)

                Text("Show a small waveform HUD while Type in Voice is recording or transcribing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard Shortcut") {
                HStack {
                    Text("Dictation Hotkey")
                    Spacer()
                    Text("⌥D")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .font(.system(.body, design: .monospaced))
                }

                Text("Press Option + D to toggle dictation on/off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text("Required for auto-paste into text fields")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    if appState.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                
                HStack {
                    Button("Request Permission") {
                        appState.requestAccessibilityPermission()
                    }
                    
                    Button("Refresh Status") {
                        appState.recheckAccessibility()
                    }
                    
                    Spacer()
                    
                    Button("Open System Settings") {
                        openAccessibilitySettings()
                    }
                }
                .buttonStyle(.link)
                
                if !appState.accessibilityGranted {
                    Text("⚠️ Without Accessibility, transcribed text will be copied to clipboard. You'll need to manually ⌘V to paste.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = Self.isRegisteredForLaunchAtLogin
        }
    }

    /// The login-item registration is owned by the system, so read it back from
    /// `SMAppService` instead of mirroring it in state that can drift out of sync.
    private static var isRegisteredForLaunchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appState.errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        // Snap the toggle back to whatever the system actually reports.
        launchAtLogin = Self.isRegisteredForLaunchAtLogin
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Transcription Tab

struct TranscriptionSettingsTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var showAPIKey = false
    @State private var apiKeySaved = false

    var body: some View {
        Form {
            Section("OpenAI API Key") {
                HStack {
                    if showAPIKey {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    Button(action: { showAPIKey.toggle() }) {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)

                    Button("Save") {
                        appState.transcriptionService.openAIAPIKey = apiKey
                        apiKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            apiKeySaved = false
                        }
                    }
                }

                if apiKeySaved {
                    Text("✓ API key saved to Keychain")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text("Used for transcription. Stored securely in your macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Language") {
                Picker("Default Language", selection: $appState.language) {
                    Text("Auto Detect").tag("auto")
                    Divider()
                    Text("English").tag("en")
                    Text("中文 (Chinese)").tag("zh")
                    Text("日本語 (Japanese)").tag("ja")
                    Text("한국어 (Korean)").tag("ko")
                    Text("Español (Spanish)").tag("es")
                    Text("Français (French)").tag("fr")
                    Text("Deutsch (German)").tag("de")
                }

                Text("Auto Detect works well for mixed Chinese and English. A specific language can improve accuracy when you know it in advance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Post-Processing") {
                Toggle("Polish punctuation and formatting", isOn: $appState.enablePostProcessing)
                Text("After transcription, use GPT-4o-mini to lightly improve readability. It keeps the original language and meaning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = appState.transcriptionService.openAIAPIKey ?? ""
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)

            Text("Type in Voice")
                .font(.title)
                .fontWeight(.bold)

            Text("v2.1.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Fast, private-feeling voice dictation for macOS.\nSpeak anywhere, and Type in Voice puts the words where your cursor is.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Powered by OpenAI transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Built with SwiftUI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
