import Cocoa
import Speech
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.voiceinput.app", category: "VoiceInputController")

/// Main coordinator for voice input functionality.
@MainActor
final class VoiceInputController {
    // MARK: - Dependencies

    private let speechRecognizer = SpeechRecognizer()
    private let textInjector = TextInjector()
    private let floatingPanel = FloatingPanel()
    private var llmRefiner: LLMRefiner?

    // MARK: - State

    private(set) var isRecording: Bool = false
    private var currentText: String = ""
    private var settings: Settings { Settings.shared }
    private var focusedAppBeforeRecording: NSRunningApplication?

    // MARK: - Initialization

    init() {
        logger.info("VoiceInputController: Initializing")
        setupSpeechRecognizer()
        setupLLMRefiner()
    }

    // MARK: - Setup

    private func setupSpeechRecognizer() {
        speechRecognizer.onPartialResult = { [weak self] text in
            Task { @MainActor in
                self?.handlePartialResult(text)
            }
        }

        speechRecognizer.onFinalResult = { [weak self] text in
            Task { @MainActor in
                self?.handleFinalResult(text)
            }
        }

        speechRecognizer.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.handleAudioLevel(level)
            }
        }
    }

    private func setupLLMRefiner() {
        llmRefiner = LLMRefiner(config: settings.llmConfig)
    }

    // MARK: - Public Methods

    /// Start monitoring (no-op for menu bar click mode).
    func startMonitoring() {
        logger.info("VoiceInputController: Ready - use startRecording() to begin")
    }

    /// Stop monitoring.
    func stopMonitoring() {
        if isRecording {
            stopRecording()
        }
        logger.info("VoiceInputController: Stopped")
    }

    /// Update LLM configuration.
    func updateLLMConfig() {
        llmRefiner = LLMRefiner(config: settings.llmConfig)
    }

    /// Start recording (public, called from AppDelegate).
    func startRecording() {
        logger.info("VoiceInputController: startRecording() called, isRecording=\(self.isRecording)")

        if isRecording {
            logger.warning("VoiceInputController: Already recording, returning")
            return
        }
        isRecording = true

        // Notify recording state change
        NotificationCenter.default.post(
            name: .voiceInputRecordingChanged,
            object: nil,
            userInfo: ["isRecording": true]
        )

        // Save currently focused app (will restore when injecting text)
        focusedAppBeforeRecording = NSWorkspace.shared.frontmostApplication
        logger.info("VoiceInputController: Saved focused app: \(self.focusedAppBeforeRecording?.localizedName ?? "nil")")

        // Reset state
        currentText = ""

        // Show floating panel
        logger.info("VoiceInputController: Showing floating panel")
        floatingPanel.show()

        // Start speech recognition
        Task {
            do {
                let locale = settings.language?.locale ?? Locale(identifier: "zh-CN")
                logger.info("VoiceInputController: Starting speech recognition with locale: \(locale.identifier)")
                try await speechRecognizer.startStreaming(locale: locale)
                logger.info("VoiceInputController: Speech recognition started successfully")
            } catch {
                logger.error("VoiceInputController: Speech recognition error: \(error.localizedDescription)")
                floatingPanel.updateText("❌ \(error.localizedDescription)")

                // Wait a moment then hide
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                floatingPanel.hide()
                isRecording = false

                // Notify state change
                NotificationCenter.default.post(
                    name: .voiceInputRecordingChanged,
                    object: nil,
                    userInfo: ["isRecording": false]
                )
            }
        }
    }

    /// Stop recording (public, called from AppDelegate).
    func stopRecording() {
        NSLog("VoiceInputController: stopRecording() called")
        logger.info("VoiceInputController: stopRecording() called, isRecording=\(self.isRecording)")

        if !isRecording {
            NSLog("VoiceInputController: Not recording, returning")
            logger.warning("VoiceInputController: Not recording, returning")
            return
        }
        isRecording = false

        // Notify recording state change
        NotificationCenter.default.post(
            name: .voiceInputRecordingChanged,
            object: nil,
            userInfo: ["isRecording": false]
        )

        // Stop speech recognition and wait for final result
        Task {
            await speechRecognizer.stopStreaming()
            NSLog("VoiceInputController: Speech recognizer stopped, current text: '\(self.currentText)'")
            logger.info("VoiceInputController: Current text: '\(self.currentText)'")

            // If we have text and LLM is enabled, refine it
            if !currentText.isEmpty && settings.llmEnabled && settings.llmConfig.isValid {
                NSLog("VoiceInputController: Calling refineAndInject")
                await refineAndInject(currentText)
            } else if !currentText.isEmpty {
                NSLog("VoiceInputController: Calling injectText directly with: '\(self.currentText)'")
                await injectText(currentText)
            } else {
                NSLog("VoiceInputController: No text to inject!")
                // No text, just hide panel
                logger.info("VoiceInputController: No text to inject, hiding panel")
                floatingPanel.updateText("没有检测到语音")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                floatingPanel.hide()
            }
        }
    }

    // MARK: - Result Handling

    private func handlePartialResult(_ text: String) {
        logger.debug("VoiceInputController: Partial result: '\(text)'")
        currentText = text
        floatingPanel.updateText(text)
    }

    private func handleFinalResult(_ text: String) {
        logger.info("VoiceInputController: Final result: '\(text)'")
        currentText = text
    }

    private func handleAudioLevel(_ level: Float) {
        floatingPanel.updateAudioLevel(level)
    }

    // MARK: - LLM Refinement

    private func refineAndInject(_ text: String) async {
        logger.info("VoiceInputController: Refining text with LLM")
        floatingPanel.showRefining()

        do {
            guard let refiner = llmRefiner else {
                throw LLMError.invalidConfiguration
            }

            let refinedText = try await refiner.refine(text: text)
            logger.info("VoiceInputController: Refined text: '\(refinedText)'")

            await injectText(refinedText)
        } catch {
            logger.error("VoiceInputController: LLM refinement error: \(error.localizedDescription)")
            await injectText(text)
        }
    }

    // MARK: - Text Injection

    private func injectText(_ text: String) async {
        NSLog("VoiceInputController: injectText called with: '\(text)'")
        logger.info("VoiceInputController: Injecting text")

        // Hide panel first
        floatingPanel.hide()
        NSLog("VoiceInputController: Panel hidden")

        // Wait for panel to fully hide
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Get target app name
        let appName = focusedAppBeforeRecording?.localizedName ?? nil
        NSLog("VoiceInputController: Target app name: \(appName ?? "nil")")
        logger.info("VoiceInputController: Target app: \(appName ?? "unknown")")

        NSLog("VoiceInputController: Calling textInjector.injectText")
        await textInjector.injectText(text, targetApp: appName)
        NSLog("VoiceInputController: textInjector returned")
        logger.info("VoiceInputController: Injected text: '\(text)'")

        // Clear saved app
        focusedAppBeforeRecording = nil
    }
}