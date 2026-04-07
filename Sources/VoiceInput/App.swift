import Cocoa

/// Application entry point for VoiceInput.
@main
struct VoiceInputApp {
    static func main() {
        // Setup app as LSUIElement (menu bar only, no Dock icon)
        let app = NSApplication.shared

        // Create and set delegate
        let delegate = AppDelegate()
        app.delegate = delegate

        // Run application
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}