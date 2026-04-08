import Cocoa

/// Application entry point for VoiceInput.
@main
struct VoiceInputApp {
    static func main() {
        // Setup app as accessory (menu bar only, no Dock icon)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        // Create and set delegate
        let delegate = AppDelegate()
        app.delegate = delegate

        // Run application
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}