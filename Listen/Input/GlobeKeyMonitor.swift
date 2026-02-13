import Cocoa
import Carbon

/// Monitors keyboard for the configured push-to-talk hotkey.
/// Supports Globe (fn), modifier-only keys (Right ⌘, etc.), and key combos (F5, ⌥Space, etc.).
/// Uses CGEvent tap with .listenOnly (needs Input Monitoring permission).
final class GlobeKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    /// Callback for hotkey recording mode — receives the captured Hotkey, then recording stops.
    var onHotkeyRecorded: ((AppConfig.Hotkey) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyDown = false

    /// The hotkey to listen for
    var hotkey: AppConfig.Hotkey = .globe

    /// When true, the next key event is captured as a new hotkey instead of triggering recording.
    var isRecordingHotkey = false

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        // Request Input Monitoring permission
        if !CGPreflightListenEventAccess() {
            listenLog("Input Monitoring not granted, requesting...")
            CGRequestListenEventAccess()
        } else {
            listenLog("Input Monitoring already granted!")
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Listen for flagsChanged (modifiers) and keyDown (regular keys)
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                                   | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<GlobeKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // Re-enable tap if it gets disabled
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let flags = event.flags
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

                // ── Hotkey Recording Mode ──
                if monitor.isRecordingHotkey {
                    if type == .flagsChanged {
                        // Only capture on press (flag appeared), not release
                        let hasModifier = !flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]).isEmpty
                        if hasModifier {
                            let captured = AppConfig.Hotkey.fromModifierEvent(keyCode: keyCode, flags: flags)
                            DispatchQueue.main.async {
                                monitor.isRecordingHotkey = false
                                monitor.onHotkeyRecorded?(captured)
                            }
                        }
                    } else if type == .keyDown {
                        let captured = AppConfig.Hotkey.fromKeyEvent(keyCode: keyCode, flags: flags)
                        DispatchQueue.main.async {
                            monitor.isRecordingHotkey = false
                            monitor.onHotkeyRecorded?(captured)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // ── Normal Hotkey Detection ──
                switch monitor.hotkey.kind {
                case .globe:
                    guard type == .flagsChanged else { break }
                    let fnPressed = flags.contains(.maskSecondaryFn)
                    let otherModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
                    let hasOther = !flags.intersection(otherModifiers).isEmpty

                    if fnPressed && !hasOther && !monitor.keyDown {
                        monitor.keyDown = true
                        DispatchQueue.main.async {
                            listenLog("HOTKEY: Globe/fn DOWN")
                            monitor.onFnDown?()
                        }
                    } else if !fnPressed && monitor.keyDown {
                        monitor.keyDown = false
                        DispatchQueue.main.async {
                            listenLog("HOTKEY: Globe/fn UP")
                            monitor.onFnUp?()
                        }
                    }

                case .modifierOnly:
                    guard type == .flagsChanged else { break }
                    let targetKeyCode = monitor.hotkey.keyCode

                    if keyCode == targetKeyCode {
                        // Check if the modifier flag for this key is now set
                        let targetModFlags = CGEventFlags(rawValue: UInt64(monitor.hotkey.modifiers))
                        let modPressed = !flags.intersection(targetModFlags).isEmpty

                        if modPressed && !monitor.keyDown {
                            // Make sure no OTHER modifiers are held
                            let allMods: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
                            let otherMods = allMods.subtracting(targetModFlags)
                            let hasOther = !flags.intersection(otherMods).isEmpty
                            if !hasOther {
                                monitor.keyDown = true
                                DispatchQueue.main.async {
                                    listenLog("HOTKEY: \(monitor.hotkey.displayName) DOWN")
                                    monitor.onFnDown?()
                                }
                            }
                        } else if !modPressed && monitor.keyDown {
                            monitor.keyDown = false
                            DispatchQueue.main.async {
                                listenLog("HOTKEY: \(monitor.hotkey.displayName) UP")
                                monitor.onFnUp?()
                            }
                        }
                    }

                case .keyCombo:
                    // For key combos, keyDown = press, we detect release via flagsChanged or keyUp
                    if type == .keyDown && keyCode == monitor.hotkey.keyCode {
                        // Check modifiers match
                        let requiredMods = CGEventFlags(rawValue: UInt64(monitor.hotkey.modifiers))
                        let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
                        let currentMods = flags.intersection(relevantFlags)
                        let requiredRelevant = requiredMods.intersection(relevantFlags)

                        if currentMods == requiredRelevant && !monitor.keyDown {
                            monitor.keyDown = true
                            DispatchQueue.main.async {
                                listenLog("HOTKEY: \(monitor.hotkey.displayName) DOWN")
                                monitor.onFnDown?()
                            }
                            // For key combos, fire "up" after a short delay since we can't
                            // easily detect keyUp with listenOnly tap for non-modifier keys.
                            // In push-to-talk, the user holds the combo — we detect release
                            // when the modifier drops or key releases.
                        }
                    } else if type == .flagsChanged && monitor.keyDown {
                        // If a modifier was part of the combo and it's now released, fire up
                        let requiredMods = CGEventFlags(rawValue: UInt64(monitor.hotkey.modifiers))
                        let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
                        let requiredRelevant = requiredMods.intersection(relevantFlags)

                        if !requiredRelevant.isEmpty {
                            let currentMods = flags.intersection(relevantFlags)
                            if currentMods != requiredRelevant {
                                monitor.keyDown = false
                                DispatchQueue.main.async {
                                    listenLog("HOTKEY: \(monitor.hotkey.displayName) UP (modifier released)")
                                    monitor.onFnUp?()
                                }
                            }
                        }
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            listenLog("CGEvent tap FAILED — need Input Monitoring permission")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        listenLog("CGEvent tap created — listening for \(hotkey.displayName) (listenOnly)")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        keyDown = false
    }

    /// Restart the monitor (e.g., when hotkey changes)
    func restart() {
        stop()
        start()
    }

    deinit {
        stop()
    }
}
