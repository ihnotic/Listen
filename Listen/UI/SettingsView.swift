import SwiftUI

/// Settings view — currently unused, all settings are inline in MenuBarView.
/// Kept as a placeholder if a standalone settings window is needed later.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Settings are in the menu bar dropdown.")
            .frame(width: 300, height: 200)
    }
}
