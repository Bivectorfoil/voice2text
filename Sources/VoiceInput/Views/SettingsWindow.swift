import Cocoa
import SwiftUI

/// LLM settings window for API configuration.
@MainActor
final class SettingsWindowController: NSWindowController {
    private var settingsView: SettingsView?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Settings"
        window.center()

        self.init(window: window)

        // Create SwiftUI view
        settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
    }

    func showWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI Settings View

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String?
    @State private var testSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("LLM API Configuration")
                .font(.headline)

            // Base URL
            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL")
                    .font(.subheadline)
                TextField("https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.subheadline)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            // Model
            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.subheadline)
                TextField("gpt-4o-mini", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            // Test result
            if let result = testResult {
                HStack {
                    Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testSuccess ? .green : .red)
                    Text(result)
                        .font(.caption)
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(isTesting || !isConfigValid)

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Spacer()

                Button("Cancel") {
                    NSApplication.shared.keyWindow?.close()
                }

                Button("Save") {
                    saveSettings()
                    NSApplication.shared.keyWindow?.close()
                }
                .disabled(!isConfigValid)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
        .onAppear {
            loadSettings()
        }
    }

    private var isConfigValid: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    private func loadSettings() {
        baseURL = settings.llmConfig.baseURL
        apiKey = settings.llmConfig.apiKey
        model = settings.llmConfig.model
    }

    private func saveSettings() {
        let config = LLMConfig(baseURL: baseURL, apiKey: apiKey, model: model)
        settings.llmConfig = config
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let config = LLMConfig(baseURL: baseURL, apiKey: apiKey, model: model)
            let refiner = LLMRefiner(config: config)

            do {
                let success = try await refiner.testConnection()
                testSuccess = success
                testResult = success ? "Connection successful!" : "Connection failed"
            } catch {
                testSuccess = false
                testResult = error.localizedDescription
            }

            isTesting = false
        }
    }
}