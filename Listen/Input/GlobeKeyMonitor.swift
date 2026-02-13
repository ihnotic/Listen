import Cocoa
import Carbon

/// Monitors the Globe (fn) key for push-to-talk.
/// Uses CGEvent tap with .listenOnly (needs Input Monitoring, NOT Accessibility).
/// Requests Input Monitoring via CGRequestListenEventAccess() which is a simpler prompt.
final class GlobeKeyMonitor {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDown = false

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        // Request Input Monitoring permission (separate from Accessibility!)
        if !CGPreflightListenEventAccess() {
            listenLog("Input Monitoring not granted, requesting...")
            CGRequestListenEventAccess()
        } else {
            listenLog("Input Monitoring already granted!")
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Listen for flagsChanged — this is how modifier keys (including fn/Globe) are detected
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

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

                // Check for fn/Globe key — .maskSecondaryFn is set when fn is held
                let fnPressed = flags.contains(.maskSecondaryFn)

                // Make sure no other modifiers are held (Cmd, Shift, Ctrl, Option)
                let otherModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
                let hasOther = !flags.intersection(otherModifiers).isEmpty

                if fnPressed && !hasOther && !monitor.fnDown {
                    monitor.fnDown = true
                    DispatchQueue.main.async {
                        listenLog("HOTKEY: Globe/fn DOWN")
                        monitor.onFnDown?()
                    }
                } else if !fnPressed && monitor.fnDown {
                    monitor.fnDown = false
                    DispatchQueue.main.async {
                        listenLog("HOTKEY: Globe/fn UP")
                        monitor.onFnUp?()
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
        listenLog("CGEvent tap created — listening for Globe/fn key (listenOnly)")
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
        fnDown = false
    }

    func upgradeToEventTapIfPossible() {}

    deinit {
        stop()
    }
}
