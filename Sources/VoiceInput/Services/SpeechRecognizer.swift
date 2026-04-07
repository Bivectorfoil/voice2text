import Speech
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.voiceinput.app", category: "SpeechRecognizer")

/// Speech recognizer using Apple's Speech framework with streaming support.
@MainActor
final class SpeechRecognizer: NSObject, ObservableObject {
    /// Current transcription text (partial or final).
    @Published var currentText: String = ""

    /// Whether recognition is currently active.
    @Published var isRecognizing: Bool = false

    /// Error message if recognition fails.
    @Published var errorMessage: String?

    /// Callback for partial results (streaming).
    var onPartialResult: ((String) -> Void)?

    /// Callback for final result.
    var onFinalResult: ((String) -> Void)?

    /// Callback for RMS audio level (0.0-1.0).
    var onAudioLevel: ((Float) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Current language being used.
    private var currentLocale: Locale?

    // MARK: - Authorization

    /// Request speech recognition authorization.
    func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Request microphone authorization on macOS.
    func requestMicrophoneAuthorization() async -> Bool {
        // On macOS, we need to actually access the audio session to trigger permission
        // AVAudioSession doesn't exist on macOS, so we use AVAudioEngine directly
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Try to install a tap - this will trigger permission request
        var permissionGranted = false

        do {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { _, _ in }
            inputNode.removeTap(onBus: 0)
            permissionGranted = true
            logger.info("Microphone permission granted")
        } catch {
            logger.error("Microphone permission denied: \(error.localizedDescription)")
        }

        return permissionGranted
    }

    /// Check if all permissions are granted.
    func checkPermissions() async -> (speech: Bool, mic: Bool) {
        // Check speech recognition permission
        let speechStatus = await requestSpeechAuthorization()
        let speechGranted = speechStatus == .authorized

        logger.info("Speech recognition status: \(speechStatus.rawValue)")

        if !speechGranted {
            logger.error("Speech recognition permission not granted")
            return (false, false)
        }

        // Check microphone permission by trying to access audio
        let micGranted = await requestMicrophoneAuthorization()

        return (speechGranted, micGranted)
    }

    // MARK: - Recognition

    /// Start streaming recognition with given locale.
    func startStreaming(locale: Locale) async throws {
        logger.info("Starting streaming for locale: \(locale.identifier)")

        // Check permissions first
        let (speechGranted, micGranted) = await checkPermissions()

        guard speechGranted else {
            logger.error("Speech recognition permission denied")
            throw SpeechError.permissionDenied
        }

        guard micGranted else {
            logger.error("Microphone permission denied")
            throw SpeechError.permissionDenied
        }

        // Create recognizer for locale
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            logger.error("Unsupported locale: \(locale.identifier)")
            throw SpeechError.unsupportedLocale(locale.identifier)
        }

        guard recognizer.isAvailable else {
            logger.error("Speech recognizer not available")
            throw SpeechError.recognitionFailed("Speech recognizer not available")
        }

        self.recognizer = recognizer
        self.currentLocale = locale
        self.currentText = ""
        self.errorMessage = nil
        self.isRecognizing = true

        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.recognitionRequest = request

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request, delegate: self)
        logger.info("Recognition task started")

        // Setup audio engine
        let inputNode = audioEngine.inputNode
        let bus = 0

        // Get the native format from the input node
        let nativeFormat = inputNode.outputFormat(forBus: bus)
        logger.info("Native audio format: \(nativeFormat.description)")

        // Install tap with the native format (let the system handle conversion)
        inputNode.installTap(
            onBus: bus,
            bufferSize: 4096,
            format: nativeFormat,
            block: { buffer, time in
                // Append to recognition request
                request.append(buffer)

                // Calculate RMS for audio level
                let rms = self.calculateRMS(buffer: buffer)
                Task { @MainActor in
                    self.onAudioLevel?(rms)
                }
            }
        )

        // Prepare and start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        logger.info("Audio engine started successfully")
    }

    /// Stop recognition and get final text.
    /// Stop streaming and wait for final result.
    func stopStreaming() async {
        logger.info("Stopping streaming")

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()

        // Wait for final result (up to 2 seconds)
        logger.info("Waiting for final recognition result...")
        var waitCount = 0
        while isRecognizing && waitCount < 20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            waitCount += 1
        }

        recognitionRequest = nil
        recognitionTask = nil
        isRecognizing = false

        logger.info("Streaming stopped, current text: '\(self.currentText)'")
    }

    /// Cancel recognition without final result.
    func cancelRecognition() {
        logger.info("Cancelling recognition")

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        isRecognizing = false
        currentText = ""
    }

    // MARK: - Audio Level

    /// Calculate RMS from audio buffer.
    private nonisolated func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        // Normalize and scale for visualization
        return min(rms * 3.0, 1.0) // Scale up for better visibility
    }
}

// MARK: - SFSpeechRecognitionTaskDelegate

extension SpeechRecognizer: SFSpeechRecognitionTaskDelegate {
    nonisolated func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didHypothesizeTranscription transcription: SFTranscription
    ) {
        Task { @MainActor in
            let text = transcription.formattedString
            currentText = text
            logger.debug("Partial result: '\(text)'")
            onPartialResult?(text)
        }
    }

    nonisolated func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didFinishRecognition recognition: SFSpeechRecognitionResult
    ) {
        Task { @MainActor in
            let text = recognition.bestTranscription.formattedString
            currentText = text
            isRecognizing = false
            logger.info("Final result: '\(text)'")
            onFinalResult?(text)
        }
    }

    nonisolated func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didFinishSuccessfully successfully: Bool
    ) {
        Task { @MainActor in
            isRecognizing = false
            if !successfully {
                errorMessage = "Recognition failed"
                logger.error("Recognition finished unsuccessfully")
            }
        }
    }

    nonisolated func speechRecognitionTask(
        _ task: SFSpeechRecognitionTask,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            isRecognizing = false
            errorMessage = error.localizedDescription
            logger.error("Recognition error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case permissionDenied
    case unsupportedLocale(String)
    case audioFormatError
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition or microphone permission denied. Please grant permission in System Settings."
        case .unsupportedLocale(let locale):
            return "Unsupported locale: \(locale)"
        case .audioFormatError:
            return "Failed to setup audio format"
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        }
    }
}