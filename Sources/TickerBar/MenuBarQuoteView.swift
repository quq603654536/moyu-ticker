import AppKit
import QuartzCore

/// Draws inside the native status button; mouse events continue to reach it.
@MainActor final class MenuBarQuoteView: NSView {
    static let transitionDuration: TimeInterval = 0.3
    private let icon = NSImageView()
    private let viewport = NSView()
    private var currentLabel: NSTextField?
    private var symbol: String?
    private var transition = UUID()
    private(set) var isAnimating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        icon.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        viewport.wantsLayer = true
        viewport.layer?.masksToBounds = true
        addSubview(viewport)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 6, y: floor((bounds.height - 16) / 2), width: 16, height: 16)
        viewport.frame = NSRect(x: 27, y: 0, width: max(0, bounds.width - 33), height: bounds.height)
        if !isAnimating { currentLabel?.frame = labelFrame }
    }
    private var labelFrame: NSRect {
        NSRect(x: 0, y: floor((viewport.bounds.height - 18) / 2), width: viewport.bounds.width, height: 18)
    }
    func display(symbol nextSymbol: String, title: NSAttributedString, animated: Bool = true) {
        if symbol == nextSymbol, let label = currentLabel {
            // A fresh price for the same security must not restart the scroll.
            label.attributedStringValue = title
            return
        }
        transition = UUID()
        let token = transition
        isAnimating = false
        let previous = currentLabel
        for view in viewport.subviews where view !== previous { view.removeFromSuperview() }
        previous?.layer?.removeAllAnimations()
        previous?.frame = labelFrame
        let label = NSTextField(labelWithAttributedString: title)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        label.frame = labelFrame
        viewport.addSubview(label)
        currentLabel = label
        symbol = nextSymbol
        guard let previous = previous, animated, window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            previous?.removeFromSuperview()
            return
        }
        let destination = labelFrame
        let distance = max(viewport.bounds.height, 22)
        label.frame = destination.offsetBy(dx: 0, dy: -distance)
        isAnimating = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            previous.animator().setFrameOrigin(destination.offsetBy(dx: 0, dy: distance).origin)
            label.animator().setFrameOrigin(destination.origin)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.transition == token else { return }
                previous.removeFromSuperview()
                self.isAnimating = false
                self.currentLabel?.frame = self.labelFrame
            }
        }
    }
}
