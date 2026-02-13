import SwiftUI

/// Settings window view.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AudioSettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Audio", systemImage: "waveform")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Recording Mode") {
                Picker("Mode", selection: $appState.config.mode) {
                    ForEach(AppConfig.RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Hotkey") {
                HStack {
                    Text("Globe (fn) key")
                    Spacer()
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                }

                Text("Hold the Globe key to record in push-to-talk mode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Model") {
                Picker("Whisper Model", selection: $appState.config.modelName) {
                    Text("Tiny (English)").tag("ggml-tiny.en")
                    Text("Base (English)").tag("ggml-base.en")
                    Text("Small (English)").tag("ggml-small.en")
                    Text("Medium (English)").tag("ggml-medium.en")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var modeDescription: String {
        switch appState.config.mode {
        case .pushToTalk:
            return "Hold the hotkey to record, release to stop and transcribe."
        case .toggleMute:
            return "Press the hotkey to start/stop recording."
        }
    }
}

// MARK: - Audio Settings

struct AudioSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Voice Activity Detection") {
                HStack {
                    Text("Energy Threshold")
                    Spacer()
                    TextField("", value: $appState.config.energyThreshold, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Min Speech (ms)")
                    Spacer()
                    TextField("", value: $appState.config.minSpeechMs, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Min Silence (ms)")
                    Spacer()
                    TextField("", value: $appState.config.minSilenceMs, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Listen")
                .font(.title)
                .fontWeight(.bold)

            Text("Lightweight local speech-to-text")
                .foregroundColor(.secondary)

            Text("Powered by whisper.cpp")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
