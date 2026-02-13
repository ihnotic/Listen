import SwiftUI

/// The main menu bar dropdown view.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                settingsContent
            } else {
                mainContent
            }
        }
        .frame(width: 280)
    }

    // MARK: - Main View

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(appState.statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Error message
            if let error = appState.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
            }

            // Model loading progress
            if appState.isModelLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 12)
            }

            Divider().padding(.vertical, 2)

            // Settings
            Button {
                showSettings = true
            } label: {
                HStack {
                    Label("Settings", systemImage: "gear")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider().padding(.vertical, 2)

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Label("Quit Listen", systemImage: "power")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Settings View (inline)

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Back button
            Button {
                showSettings = false
                appState.stopRecordingHotkey() // Cancel recording if user navigates away
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                    Text("Back")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider().padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 14) {
                // Recording Mode
                settingsSection("Recording Mode") {
                    HStack(spacing: 8) {
                        modeButton("Push to Talk", mode: .pushToTalk)
                        modeButton("Toggle", mode: .toggleMute)
                    }

                    Text(modeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Hotkey
                settingsSection("Hotkey") {
                    Button {
                        if appState.isRecordingHotkey {
                            appState.stopRecordingHotkey()
                        } else {
                            appState.startRecordingHotkey()
                        }
                    } label: {
                        HStack {
                            if appState.isRecordingHotkey {
                                Text("Press any key...")
                                    .font(.callout)
                                    .foregroundColor(.accentColor)
                            } else {
                                Text(appState.config.hotkey.displayName)
                                    .font(.callout)
                            }
                            Spacer()
                            Image(systemName: appState.isRecordingHotkey ? "keyboard" : "pencil")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(appState.isRecordingHotkey ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.isRecordingHotkey ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("Click to change, then press your desired key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            content()
        }
    }

    private func modeButton(_ label: String, mode: AppConfig.RecordingMode) -> some View {
        Button {
            appState.config.mode = mode
        } label: {
            Text(label)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(appState.config.mode == mode ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(appState.config.mode == mode ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var modeDescription: String {
        switch appState.config.mode {
        case .pushToTalk:
            return "Hold the hotkey to record, release to stop."
        case .toggleMute:
            return "Press the hotkey to start/stop recording."
        }
    }

    private var statusColor: Color {
        if appState.isRecording {
            return .red
        } else if appState.isModelLoaded {
            return .green
        } else if appState.isModelLoading {
            return .orange
        } else {
            return .gray
        }
    }
}
