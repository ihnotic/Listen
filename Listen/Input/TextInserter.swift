import Cocoa

/// Inserts text into the active application via clipboard + CGEvent Cmd+V.
/// Ported from electron/resources/macos-paste-helper.swift and main.js typeIntoActiveApp.
final class TextInserter {
    private let queue = DispatchQueue(label: "com.listen.textInserter")
    private let semaphore = DispatchSemaphore(value: 1)

    /// Insert text into whatever app currently has keyboard focus.
    func insertText(_ text: String) {
        let payload = text.hasSuffix(" ") ? text : text + " "

        queue.async { [weak self] in
            self?.semaphore.wait()
            defer { self?.semaphore.signal() }

            listenLog("TextInserter: writing '\(payload)' to clipboard")

            // Save current clipboard
            let pasteboard = NSPasteboard.general
            let previousContents = pasteboard.string(forType: .string)

            // Write transcription to clipboard
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)

            // Small delay to ensure clipboard is written
            Thread.sleep(forTimeInterval: 0.05)

            // Simulate Cmd+V at HID level
            listenLog("TextInserter: simulating Cmd+V paste")
            Self.simulatePaste()

            // Restore clipboard after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let pb = NSPasteboard.general
                pb.clearContents()
                if let prev = previousContents {
                    pb.setString(prev, forType: .string)
                }
                listenLog("TextInserter: clipboard restored")
            }
        }
    }

    /// Post Cmd+V via CGEvent at HID level — bypasses focus issues.
    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)

        // keycode 9 = 'v'
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            NSLog("TextInserter: Failed to create CGEvent")
            return
        }

        keyDown.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)

        keyUp.flags = .maskCommand
        keyUp.post(tap: .cghidEventTap)
    }
}
