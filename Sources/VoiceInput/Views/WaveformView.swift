import Cocoa

/// Animated waveform view with 5 bars driven by audio RMS level.
final class WaveformView: NSView {
    // MARK: - Constants

    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 8
    private let minHeight: CGFloat = 16
    private let maxHeight: CGFloat = 44

    /// Weight for each bar (center high, sides low).
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

    /// Random jitter range (±4%).
    private let jitterRange: CGFloat = 0.04

    /// Attack time for level increase (40%).
    private let attackFactor: CGFloat = 0.4

    /// Release time for level decrease (15%).
    private let releaseFactor: CGFloat = 0.15

    // MARK: - UI Components

    private var bars: [NSView] = []
    private var targetHeights: [CGFloat] = []
    private var currentHeights: [CGFloat] = []
    private var jitterOffsets: [CGFloat] = []

    // MARK: - State

    private var isAnimating: Bool = false
    private var displayLink: CVDisplayLink?
    private var lastLevel: Float = 0

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBars()
    }

    private func setupBars() {
        wantsLayer = true

        // Create bars
        for i in 0..<barCount {
            let bar = NSView(frame: NSRect.zero)
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.cgColor
            bar.layer?.cornerRadius = barWidth / 2

            addSubview(bar)
            bars.append(bar)
            targetHeights.append(minHeight)
            currentHeights.append(minHeight)
            jitterOffsets.append(0)
        }

        // Initial layout
        layoutBars()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutBars()
    }

    private func layoutBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalWidth) / 2
        let centerY = bounds.height / 2

        for (i, bar) in bars.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let height = currentHeights[i]
            let y = centerY - height / 2

            bar.frame = NSRect(x: x, y: y, width: barWidth, height: height)
        }
    }

    // MARK: - Animation Control

    /// Start waveform animation loop.
    func startAnimation() {
        if isAnimating { return }
        isAnimating = true

        // Create display link for smooth animation
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)

        if let link = displayLink {
            CVDisplayLinkSetOutputCallback(link, { _, inNow, inOutputTime, _, _, displayLinkContext in
                let view = Unmanaged<WaveformView>.fromOpaque(displayLinkContext!).takeUnretainedValue()
                DispatchQueue.main.async {
                    view.updateAnimation()
                }
                return kCVReturnSuccess
            }, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(link)
        }
    }

    /// Stop waveform animation.
    func stopAnimation() {
        isAnimating = false

        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }

        // Reset bars to minimum height
        for i in 0..<barCount {
            currentHeights[i] = minHeight
            targetHeights[i] = minHeight
        }
        layoutBars()
    }

    // MARK: - Level Update

    /// Update audio level (0.0-1.0).
    func updateLevel(_ level: Float) {
        lastLevel = level

        // Calculate target heights based on level and weights
        let levelRange = maxHeight - minHeight

        for i in 0..<barCount {
            let weightedLevel = CGFloat(level) * weights[i]
            let jitter = CGFloat.random(in: -jitterRange...jitterRange) * weightedLevel
            jitterOffsets[i] = jitter

            let baseHeight = minHeight + weightedLevel * levelRange
            targetHeights[i] = min(max(baseHeight + jitter, minHeight), maxHeight)
        }
    }

    // MARK: - Animation Loop

    private func updateAnimation() {
        if !isAnimating { return }

        // Apply envelope (attack/release) to smooth transitions
        for i in 0..<barCount {
            let target = targetHeights[i]
            let current = currentHeights[i]

            // Apply attack (fast increase) or release (slow decrease)
            if target > current {
                // Attack: quick increase
                currentHeights[i] = current + (target - current) * attackFactor
            } else {
                // Release: slow decrease
                currentHeights[i] = current + (target - current) * releaseFactor
            }

            // Add small random jitter for organic feel
            let organicJitter = CGFloat.random(in: -1...1)
            currentHeights[i] = max(minHeight, min(maxHeight, currentHeights[i] + organicJitter))
        }

        // Update layout without full animation (for smooth per-frame updates)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutBars()
        CATransaction.commit()
    }
}