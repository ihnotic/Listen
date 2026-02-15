import Cocoa
import ApplicationServices

/// Inserts text into the active application using the Accessibility API.
/// Falls back to clipboard + CGEvent Cmd+V if AX insertion fails.
final class TextInserter {
    private let queue = DispatchQueue(label: "com.listen.textInserter")
    private let semaphore = DispatchSemaphore(value: 1)

    /// Insert text into whatever app currently has keyboard focus.
    /// Uses clipboard + Cmd+V — the only method that reliably works across all apps including Electron.
    func insertText(_ text: String) {
        let payload = text.hasSuffix(" ") ? text : text + " "

        queue.async { [weak self] in
            self?.semaphore.wait()
            defer { self?.semaphore.signal() }

            // Wait for physical modifier keys to settle after hotkey release
            Thread.sleep(forTimeInterval: 0.3)

            Self.insertViaClipboard(payload)
        }
    }

    /// Fallback: clipboard + CGEvent Cmd+V paste.
    private static func insertViaClipboard(_ text: String) {
        listenLog("TextInserter: writing '\(text)' to clipboard")

        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Thread.sleep(forTimeInterval: 0.1)

        listenLog("TextInserter: simulating Cmd+V paste")
        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let prev = previousContents {
                pb.setString(prev, forType: .string)
            }
            listenLog("TextInserter: clipboard restored")
        }
    }

    /// Post Cmd+V via CGEvent.
    private static func simulatePaste() {
        let src = CGEventSource(stateID: .privateState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            listenLog("TextInserter: Failed to create CGEvent")
            return
        }
        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
}
