import Foundation

/// Manages hotkey events (backtick key).
final class HotkeyManager {
    var onActivate: (() -> Void)?
    var onDeactivate: (() -> Void)?

    var mode: AppConfig.RecordingMode = .pushToTalk
    private(set) var isActive = false

    /// Called when hotkey is pressed down.
    func handleFnDown() {
        switch mode {
        case .pushToTalk:
            if !isActive {
                isActive = true
                onActivate?()
            }

        case .toggleMute:
            isActive.toggle()
            if isActive {
                onActivate?()
            } else {
                onDeactivate?()
            }
        }
    }

    /// Called when hotkey is released.
    func handleFnUp() {
        guard mode == .pushToTalk, isActive else { return }
        isActive = false
        onDeactivate?()
    }
}
