import Cocoa
import Carbon
import CoreFoundation
import os.log

private let logger = Logger(subsystem: "com.voiceinput.app", category: "TextInjector")

/// Text injector using clipboard + AppleScript Cmd+V paste method.
/// Handles CJK input method switching to avoid interception.
final class TextInjector {
    /// Saved clipboard content before injection.
    private var savedClipboardContent: String?

    /// Saved input source before switching to ASCII.
    private var savedInputSource: TISInputSource?

    /// Whether we switched from CJK input.
    private var switchedFromCJK: Bool = false

    /// Target application name for paste.
    private var targetAppName: String?

    /// Inject text into the currently focused input field.
    func injectText(_ text: String, targetApp: String? = nil) async {
        NSLog("TextInjector: injectText called with: '\(text)'")
        logger.info("TextInjector: injectText called with: '\(text)'")

        guard !text.isEmpty else {
            NSLog("TextInjector: Empty text, skipping")
            logger.warning("TextInjector: Empty text, skipping")
            return
        }

        // Store target app name
        targetAppName = targetApp

        // Step 1: Save current clipboard
        saveClipboard()
        NSLog("TextInjector: Clipboard saved")
        logger.info("TextInjector: Clipboard saved")

        // Step 2: Check if CJK input method is active
        let isCJK = isCJKInputMethodActive()
        NSLog("TextInjector: CJK input method active: \(isCJK)")
        logger.info("TextInjector: CJK input method active: \(isCJK)")

        if isCJK {
            NSLog("TextInjector: Switching to ASCII input")
            switchToASCIIInput()
            switchedFromCJK = true
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        // Step 3: Set text to clipboard
        setTextToClipboard(text)
        NSLog("TextInjector: Text set to clipboard: '\(text)'")
        logger.info("TextInjector: Text set to clipboard")

        // Wait for clipboard to be ready
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Step 4: Use AppleScript to paste (works with any app)
        NSLog("TextInjector: About to call pasteViaAppleScript")
        pasteViaAppleScript()
        NSLog("TextInjector: pasteViaAppleScript returned")

        // Step 5: Restore input method if we switched
        if switchedFromCJK {
            try? await Task.sleep(nanoseconds: 100_000_000)
            NSLog("TextInjector: Restoring original input method")
            restoreInputMethod()
            switchedFromCJK = false
        }

        // Step 6: Restore clipboard after delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        restoreClipboard()
        NSLog("TextInjector: Clipboard restored")
        logger.info("TextInjector: Clipboard restored")
    }

    /// Paste using AppleScript - activates target app and sends Cmd+V
    private func pasteViaAppleScript() {
        NSLog("TextInjector: pasteViaAppleScript() called")

        var script: String

        if let appName = targetAppName, !appName.isEmpty {
            // Activate specific app then paste
            script = """
            tell application "\(appName)"
                activate
            end tell
            """
            NSLog("TextInjector: First activating app: \(appName)")
            logger.info("TextInjector: Activating target app: \(appName)")

            // Run activation script first
            let activationResult = runAppleScript(script)
            NSLog("TextInjector: Activation result: \(activationResult)")

            // Wait for app to activate
            Thread.sleep(forTimeInterval: 0.3)

            // Then run paste script
            script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
            NSLog("TextInjector: Now sending Cmd+V")
            let pasteResult = runAppleScript(script)
            NSLog("TextInjector: Paste result: \(pasteResult)")
            logger.info("TextInjector: Paste result: \(pasteResult)")
        } else {
            // Just paste without activating specific app
            script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
            NSLog("TextInjector: Using AppleScript without specific app")
            let result = runAppleScript(script)
            NSLog("TextInjector: Result: \(result)")
            logger.info("TextInjector: Paste result: \(result)")
        }
    }

    /// Run AppleScript and return success status using NSAppleScript
    private func runAppleScript(_ script: String) -> Bool {
        NSLog("TextInjector: Running NSAppleScript")

        let appleScript = NSAppleScript(source: script)

        var errorDict: NSDictionary?
        let result = appleScript?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            NSLog("TextInjector: NSAppleScript error: \(errorMessage)")
            NSLog("TextInjector: Full error dict: \(error)")
            logger.error("TextInjector: NSAppleScript error: \(errorMessage)")
            return false
        }

        NSLog("TextInjector: NSAppleScript executed successfully")
        return true
    }

    // MARK: - Clipboard Operations

    private func saveClipboard() {
        let pasteboard = NSPasteboard.general
        savedClipboardContent = pasteboard.string(forType: .string)
        logger.debug("TextInjector: Saved clipboard content length: \(self.savedClipboardContent?.count ?? 0)")
    }

    private func setTextToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func restoreClipboard() {
        guard let saved = savedClipboardContent else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(saved, forType: .string)
        savedClipboardContent = nil
    }

    // MARK: - Input Method Detection & Switching

    /// Check if current input source is CJK (Chinese, Japanese, Korean).
    private func isCJKInputMethodActive() -> Bool {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }

        // Get input source ID
        guard let sourceID = getInputSourceID(currentSource) else {
            return false
        }

        logger.debug("TextInjector: Current input source ID: \(sourceID)")

        // CJK input sources typically contain these patterns
        let cjkPatterns = [
            "com.apple.keylayout.SCIM",     // Simplified Chinese
            "com.apple.keylayout.TCIM",     // Traditional Chinese
            "com.apple.inputmethod.Japanese", // Japanese
            "com.apple.keylayout.Korean",   // Korean
            "com.apple.inputmethod.Korean",  // Korean IM
            "com.sogou.inputmethod",        // Sogou Pinyin
            "com.baidu.inputmethod",        // Baidu Input
            "com.google.inputmethod",       // Google Input
            "com.sunpinyin.inputmethod",    // SunPinyin
            "Pinyin",                       // Generic pinyin
        ]

        for pattern in cjkPatterns {
            if sourceID.contains(pattern) {
                logger.info("TextInjector: Detected CJK input: \(pattern)")
                return true
            }
        }

        // Check source languages
        let languages = getInputSourceLanguages(currentSource)
        for lang in languages {
            if ["zh", "ja", "ko"].contains(lang) {
                logger.info("TextInjector: Detected CJK language: \(lang)")
                return true
            }
        }

        return false
    }

    /// Switch to ASCII input source (ABC/US keyboard).
    private func switchToASCIIInput() {
        // Save current input source
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            savedInputSource = current
            logger.debug("TextInjector: Saved current input source")
        }

        // Find ASCII input source
        guard let asciiSource = findASCIIInputSource() else {
            logger.warning("TextInjector: No ASCII input source found")
            return
        }

        // Switch to ASCII
        TISSelectInputSource(asciiSource)
        logger.info("TextInjector: Switched to ASCII input")
    }

    /// Restore original input source.
    private func restoreInputMethod() {
        guard let saved = savedInputSource else { return }
        TISSelectInputSource(saved)
        savedInputSource = nil
        logger.info("TextInjector: Restored original input method")
    }

    /// Find an ASCII input source to switch to.
    private func findASCIIInputSource() -> TISInputSource? {
        // Get all enabled input sources
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        logger.debug("TextInjector: Found \(inputSources.count) input sources")

        // Look for ABC or US keyboard
        for source in inputSources {
            guard let sourceID = getInputSourceID(source) else { continue }

            // Prefer ABC layout
            if sourceID.contains("com.apple.keylayout.ABC") ||
               sourceID.contains("com.apple.keylayout.US") ||
               sourceID == "com.apple.keylayout.ABC" ||
               sourceID == "com.apple.keylayout.US" {
                logger.info("TextInjector: Found ASCII input: \(sourceID)")
                return source
            }
        }

        // Look for any ASCII-capable layout
        for source in inputSources {
            if let isASCIICapable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) {
                let capable = unsafeBitCast(isASCIICapable, to: Bool.self)
                if capable {
                    guard let sourceID = getInputSourceID(source) else { continue }
                    // Avoid CJK sources even if ASCII capable
                    if !sourceID.contains("SCIM") && !sourceID.contains("TCIM") &&
                       !sourceID.contains("Japanese") && !sourceID.contains("Korean") &&
                       !sourceID.contains("Pinyin") {
                        logger.info("TextInjector: Found ASCII-capable input: \(sourceID)")
                        return source
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Input Source Properties

    private func getInputSourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return unsafeBitCast(ptr, to: CFString.self) as String
    }

    private func getInputSourceLanguages(_ source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        guard let languages = unsafeBitCast(ptr, to: CFArray.self) as? [CFString] else { return [] }
        return languages.map { $0 as String }
    }
}