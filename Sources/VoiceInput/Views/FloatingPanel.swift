import Cocoa

/// Floating capsule panel for displaying recording status and transcription.
final class FloatingPanel: NSPanel {
    // MARK: - Constants

    private let minPanelHeight: CGFloat = 56
    private let maxPanelHeight: CGFloat = 200
    private let cornerRadius: CGFloat = 28
    private let minPanelWidth: CGFloat = 350
    private let maxPanelWidth: CGFloat = 600
    private let waveformWidth: CGFloat = 60
    private let horizontalPadding: CGFloat = 16

    // MARK: - UI Components

    private var visualEffectView: NSVisualEffectView!
    private var waveformView: WaveformView!
    private var textView: NSTextField!
    private var containerStack: NSStackView!

    // MARK: - State

    private var currentText: String = ""
    private var centerX: CGFloat = 0

    // MARK: - Initialization

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: minPanelWidth, height: minPanelHeight),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )

        // Configure panel
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isOpaque = false
        self.alphaValue = 0

        setupViews()
    }

    convenience init() {
        self.init(
            contentRect: NSRect.zero,
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )
    }

    private func setupViews() {
        // Create visual effect view (hud material)
        visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: minPanelWidth, height: minPanelHeight))
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.masksToBounds = true

        // Create waveform view
        waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: waveformWidth, height: minPanelHeight))
        waveformView.wantsLayer = true

        // Create text view with word wrapping
        textView = NSTextField(wrappingLabelWithString: "正在聆听...")
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.alignment = .left
        textView.lineBreakMode = .byWordWrapping
        textView.maximumNumberOfLines = 3
        textView.usesSingleLineMode = false

        // Create container stack
        containerStack = NSStackView(frame: visualEffectView.bounds)
        containerStack.orientation = .horizontal
        containerStack.alignment = .centerY
        containerStack.spacing = 8
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        // Add views to stack
        containerStack.addView(waveformView, in: .leading)
        containerStack.addView(textView, in: .leading)

        // Configure constraints
        waveformView.widthAnchor.constraint(equalToConstant: waveformWidth).isActive = true
        textView.widthAnchor.constraint(lessThanOrEqualToConstant: maxPanelWidth - waveformWidth - horizontalPadding * 2 - 8).isActive = true

        // Add stack to visual effect view
        visualEffectView.addSubview(containerStack)

        // Configure stack constraints
        NSLayoutConstraint.activate([
            containerStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: horizontalPadding),
            containerStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -horizontalPadding),
            containerStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 8),
            containerStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -8)
        ])

        // Set content view
        contentView = visualEffectView
    }

    // MARK: - NSPanel Overrides

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public Methods

    /// Show panel with spring animation.
    func show() {
        print("FloatingPanel: show() called")

        // Reset state first
        resetSize()

        // Position at screen bottom center
        positionAtScreenBottomCenter()

        // Make visible immediately
        alphaValue = 0
        makeKeyAndOrderFront(nil)

        // Spring animation for entry
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1.0
        })

        // Start waveform animation
        waveformView.startAnimation()

        print("FloatingPanel: Panel shown and visible")
    }

    /// Hide panel with scale animation.
    func hide() {
        print("FloatingPanel: hide() called")

        // Stop waveform animation
        waveformView.stopAnimation()

        // Fade out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            print("FloatingPanel: Panel hidden")
        })
    }

    /// Update transcription text.
    func updateText(_ text: String) {
        currentText = text
        textView.stringValue = text.isEmpty ? "正在聆听..." : text

        // Adjust panel width based on text length
        resizePanelForText(text)
    }

    /// Resize panel based on text content.
    private func resizePanelForText(_ text: String) {
        // Calculate required width
        let textSize = textView.sizeThatFits(NSSize(width: maxPanelWidth, height: maxPanelHeight))
        let requiredWidth = min(max(textSize.width + waveformWidth + horizontalPadding * 2 + 16, minPanelWidth), maxPanelWidth)

        // Animate width change
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            let newFrame = NSRect(
                x: centerX - requiredWidth / 2,
                y: frame.origin.y,
                width: requiredWidth,
                height: frame.height
            )
            animator().setFrame(newFrame, display: true)
        })
    }

    /// Show refining status.
    func showRefining() {
        waveformView.stopAnimation()
        textView.stringValue = "优化中..."
        textView.textColor = NSColor.systemYellow
    }

    /// Update audio level for waveform.
    func updateAudioLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }

    // MARK: - Positioning

    private func positionAtScreenBottomCenter() {
        guard let screen = NSScreen.main else {
            print("FloatingPanel: No main screen found")
            return
        }

        let screenFrame = screen.visibleFrame
        let panelWidth = frame.width

        // Store center X for later resizing
        centerX = screenFrame.midX

        let x = centerX - panelWidth / 2
        let y = screenFrame.origin.y + 100 // 100px from bottom

        setFrameOrigin(NSPoint(x: x, y: y))
        print("FloatingPanel: Positioned at (\(x), \(y)), centerX=\(self.centerX)")
    }

    private func resetSize() {
        currentText = ""
        textView.stringValue = "正在聆听..."
        textView.textColor = .white

        // Reset to minimum size
        let newFrame = NSRect(
            x: centerX - minPanelWidth / 2,
            y: frame.origin.y,
            width: minPanelWidth,
            height: minPanelHeight
        )
        setFrame(newFrame, display: false)
    }
}