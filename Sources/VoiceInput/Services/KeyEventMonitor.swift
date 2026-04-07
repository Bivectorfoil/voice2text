import Cocoa
import Carbon

/// Global Fn key event monitor using CGEventTap.
final class KeyEventMonitor {
    /// Callback when Fn key is pressed down.
    var onTapDown: (() -> Void)?

    /// Callback when Fn key is released.
    var onTapUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Fn key keycode (63).
    private static let fnKeycode: Int64 = 63

    /// Track Fn key state to detect press/release
    private var fnKeyPressed: Bool = false

    /// Start monitoring Fn key events globally.
    /// Returns false if accessibility permission is not granted.
    @discardableResult
    func start() -> Bool {
        // Check accessibility permission
        let trusted = AXIsProcessTrusted()

        print("KeyEventMonitor: Accessibility permission status: \(trusted)")

        if !trusted {
            print("KeyEventMonitor: Accessibility permission required - please enable in System Settings")
            return false
        }

        // Create event tap using C function
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(
                (1 << CGEventType.keyDown.rawValue) |
                (1 << CGEventType.keyUp.rawValue) |
                (1 << CGEventType.flagsChanged.rawValue)
            ),
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passRetained(event)
                }
                let monitor = Unmanaged<KeyEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            print("KeyEventMonitor: Failed to create event tap - this usually means accessibility permission is not granted")
            return false
        }

        eventTap = tap

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        // Add to run loop
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

        print("KeyEventMonitor: Started successfully - press Fn key to test")
        return true
    }

    /// Stop monitoring.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        fnKeyPressed = false
        print("KeyEventMonitor: Stopped")
    }

    /// Handle event callback.
    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Debug: Log all events to see what's happening
        // print("KeyEventMonitor: Event type=\(type), keycode=\(keycode), flags=\(flags)")

        // On macOS, Fn key is detected via flagsChanged with .maskSecondaryFn or .function flag
        // Different MacBooks may use different detection methods

        // Method 1: Check for Fn flag change (most common)
        let hasFnFlag = flags.contains(.maskSecondaryFn)

        // Method 2: Some MacBooks report Fn as keycode 63 with flagsChanged
        let isFnKeycode = keycode == Self.fnKeycode

        // Detect Fn key press/release
        if type == .flagsChanged {
            // Check if Fn flag state changed
            if hasFnFlag != fnKeyPressed {
                fnKeyPressed = hasFnFlag

                if hasFnFlag {
                    print("KeyEventMonitor: Fn key PRESSED (via flag)")
                    onTapDown?()
                } else {
                    print("KeyEventMonitor: Fn key RELEASED (via flag)")
                    onTapUp?()
                }

                // Suppress the Fn key event to prevent emoji picker
                return nil
            }

            // Check if it's Fn keycode
            if isFnKeycode {
                // For keycode-based detection, we need to determine press vs release
                // The presence of the flag indicates press, absence indicates release
                let isPressed = hasFnFlag

                if isPressed && !fnKeyPressed {
                    fnKeyPressed = true
                    print("KeyEventMonitor: Fn key PRESSED (via keycode)")
                    onTapDown?()
                } else if !isPressed && fnKeyPressed {
                    fnKeyPressed = false
                    print("KeyEventMonitor: Fn key RELEASED (via keycode)")
                    onTapUp?()
                }

                return nil
            }
        }

        // Also check for keyDown/keyUp events with Fn keycode
        if isFnKeycode {
            if type == .keyDown && !fnKeyPressed {
                fnKeyPressed = true
                print("KeyEventMonitor: Fn key PRESSED (via keyDown)")
                onTapDown?()
            } else if type == .keyUp && fnKeyPressed {
                fnKeyPressed = false
                print("KeyEventMonitor: Fn key RELEASED (via keyUp)")
                onTapUp?()
            }
            // Suppress the Fn key event
            return nil
        }

        // Pass through other events
        return Unmanaged.passRetained(event)
    }

    /// Check if accessibility permission is granted.
    static func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }
}