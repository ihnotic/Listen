import Cocoa
import SwiftUI

/// Floating, non-activating pill window that shows a waveform during recording.
/// Uses NSPanel so it doesn't steal focus from the active app.
final class RecordingPillWindow {
    static let shared = RecordingPillWindow()

    private var panel: NSPanel?
    private let levelStore = AudioLevelStore()

    private init() {}

    /// Push an audio level (RMS) to the waveform. Called from main thread.
    func pushLevel(_ rms: Float) {
        levelStore.push(rms)
    }

    func show() {
        guard panel == nil else { return }

        let pillView = RecordingPillView(levelStore: levelStore)
        let hostingView = NSHostingView(rootView: pillView)

        let pillWidth: CGFloat = 150
        let pillHeight: CGFloat = 32

        hostingView.frame = NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight)

        // Position at bottom-center of main screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - pillWidth / 2
        let y = screenFrame.minY + 40

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: pillWidth, height: pillHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        panel.hidesOnDeactivate = false

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
        levelStore.reset()
    }
}
