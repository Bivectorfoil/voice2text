import Cocoa
import Speech
import os.log

private let logger = Logger(subsystem: "com.voiceinput.app", category: "AppDelegate")

/// Application delegate for menu bar setup and lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var voiceInputController: VoiceInputController?
    private var settingsWindowController: SettingsWindowController?

    /// Track recording state
    private var isRecording: Bool = false {
        didSet {
            logger.info("AppDelegate: isRecording changed to \(self.isRecording)")
            updateMenuBarIcon()
        }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("VoiceInput: Application launched")

        // Request accessibility permission first (needed for text injection)
        requestAccessibilityPermission()

        // Request speech recognition permission
        requestPermissions()

        // Setup menu bar
        setupMenuBar()

        // Setup voice input controller
        voiceInputController = VoiceInputController()
        voiceInputController?.startMonitoring()

        // Observe recording state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recordingStateChanged),
            name: .voiceInputRecordingChanged,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        voiceInputController?.stopMonitoring()
        logger.info("VoiceInput: Application terminated")
    }

    // MARK: - Permissions

    private func requestAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        logger.info("Initial accessibility trusted: \(trusted)")

        if !trusted {
            // Request accessibility permission with prompt - this will show system dialog
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            logger.info("Accessibility permission dialog shown")

            // Show alert explaining why we need it
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showPermissionAlert(
                    title: "需要辅助功能权限",
                    message: "VoiceInput 需要「辅助功能」权限才能将文字插入输入框。\n\n请在系统设置中勾选 VoiceInput。"
                )
            }
        }
    }

    private func requestPermissions() {
        Task {
            // Request speech recognition permission
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }

            logger.info("Speech recognition authorization status: \(status.rawValue)")

            if status != .authorized {
                showPermissionAlert(
                    title: "语音识别权限",
                    message: "请在「系统设置」>「隐私与安全性」>「语音识别」中允许 VoiceInput。"
                )
            }
        }
    }

    private func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!)
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        // Set initial icon
        updateMenuBarIcon()

        // Handle clicks - left click toggles recording, right click shows menu
        button.action = #selector(handleButtonClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        logger.info("AppDelegate: Menu bar setup complete")
    }

    @objc private func handleButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent

        logger.info("AppDelegate: Button clicked, event type: \(event?.type.rawValue.description ?? "nil")")

        if event?.type == .rightMouseDown {
            // Show menu on right click
            logger.info("AppDelegate: Right click - showing menu")
            showMenu()
        } else {
            // Toggle recording on left click
            logger.info("AppDelegate: Left click - toggling recording")
            toggleRecording()
        }
    }

    private func showMenu() {
        let menu = buildMenu()

        guard let button = statusItem?.button else { return }

        // Position menu below the button
        let menuLocation = NSPoint(x: 0, y: button.bounds.height)

        menu.popUp(positioning: nil, at: menuLocation, in: button)
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let iconName = isRecording ? "mic.circle.fill" : "mic.fill"

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "VoiceInput") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = !isRecording
            button.image = image

            button.contentTintColor = isRecording ? .systemRed : .labelColor
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Toggle recording
        let toggleItem = NSMenuItem(
            title: isRecording ? "⏹ 停止录音" : "🎤 开始录音",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Language submenu
        let languageMenuItem = NSMenuItem(title: "语言", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        for lang in Language.allCases {
            let item = NSMenuItem(
                title: "\(lang.flagIcon) \(lang.displayName)",
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang
            item.target = self

            if lang.rawValue == Settings.shared.selectedLanguage {
                item.state = .on
            }

            languageMenu.addItem(item)
        }

        languageMenuItem.submenu = languageMenu
        menu.addItem(languageMenuItem)

        // LLM submenu
        let llmMenuItem = NSMenuItem(title: "LLM 优化", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let enableItem = NSMenuItem(
            title: "启用 LLM 文本优化",
            action: #selector(toggleLLM(_:)),
            keyEquivalent: ""
        )
        enableItem.target = self
        enableItem.state = Settings.shared.llmEnabled ? .on : .off
        llmMenu.addItem(enableItem)

        let settingsItem = NSMenuItem(
            title: "LLM 设置...",
            action: #selector(showLLMSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        llmMenuItem.submenu = llmMenu
        menu.addItem(llmMenuItem)

        menu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "关于 VoiceInput",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(
            title: "退出 VoiceInput",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Actions

    @objc func toggleRecording() {
        logger.info("AppDelegate: toggleRecording(), current isRecording=\(self.isRecording)")

        if isRecording {
            voiceInputController?.stopRecording()
            isRecording = false
        } else {
            voiceInputController?.startRecording()
            isRecording = true
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? Language else { return }

        Settings.shared.selectedLanguage = language.rawValue

        if let menu = sender.menu {
            for item in menu.items {
                item.state = item == sender ? .on : .off
            }
        }

        logger.info("AppDelegate: Selected language: \(language.displayName)")
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        Settings.shared.llmEnabled = !Settings.shared.llmEnabled
        sender.state = Settings.shared.llmEnabled ? .on : .off
        voiceInputController?.updateLLMConfig()
    }

    @objc private func showLLMSettings(_ sender: NSMenuItem) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    @objc private func recordingStateChanged(_ notification: Notification) {
        if let recording = notification.userInfo?["isRecording"] as? Bool {
            isRecording = recording
        }
    }
}

extension Notification.Name {
    static let voiceInputRecordingChanged = Notification.Name("voiceInputRecordingChanged")
}