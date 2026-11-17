import AppKit
import SwiftUI

/// Native hit testing keeps the header draggable even when the app is inactive
/// and the rest of the panel is fully transparent.
struct HoverToolbar: NSViewRepresentable {
    let pinned: Bool
    let transparent: Bool
    let pin: () -> Void
    let transparency: () -> Void
    let close: () -> Void

    func makeNSView(context: Context) -> ToolbarView { ToolbarView() }
    func updateNSView(_ view: ToolbarView, context: Context) {
        view.update(pinned: pinned, transparent: transparent)
        view.pinAction = pin
        view.transparencyAction = transparency
        view.closeAction = close
    }

    final class ToolbarView: NSView {
        private let title = PassthroughLabel(labelWithString: "自选行情")
        private let grip = PassthroughImage()
        private let pinButton = ToolbarButton()
        private let transparencyButton = ToolbarButton()
        private let closeButton = ToolbarButton()
        private var pinned = false
        var pinAction: (() -> Void)?
        var transparencyAction: (() -> Void)?
        var closeAction: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
            layer?.cornerRadius = 7
            layer?.borderWidth = 0.5
            layer?.borderColor = NSColor(Palette.line).cgColor
            title.font = .systemFont(ofSize: 10, weight: .medium)
            title.textColor = NSColor(Palette.ink)
            title.lineBreakMode = .byTruncatingTail
            grip.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            grip.contentTintColor = NSColor(Palette.muted)
            grip.imageScaling = .scaleProportionallyDown
            addSubview(title); addSubview(grip)
            configure(pinButton, action: #selector(togglePin))
            configure(transparencyButton, action: #selector(toggleTransparency))
            configure(closeButton, action: #selector(closePanel))
        }
        required init?(coder: NSCoder) { return nil }

        private func configure(_ button: NSButton, action: Selector) {
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.title = ""
            button.imagePosition = .imageOnly
            button.focusRingType = .none
            button.target = self
            button.action = action
            addSubview(button)
        }
        func update(pinned: Bool, transparent: Bool) {
            self.pinned = pinned
            layer?.backgroundColor = transparent ? NSColor.clear.cgColor : NSColor.white.withAlphaComponent(0.96).cgColor
            layer?.borderWidth = transparent ? 0 : 0.5
            title.stringValue = pinned ? "行情 · 已固定" : "行情"
            toolTip = pinned ? "按住标题栏拖动窗口" : "点击图钉固定后，可拖动标题栏移动"
            setIcon(pinButton, symbol: pinned ? "pin.fill" : "pin", active: pinned, help: pinned ? "取消固定" : "固定窗口")
            setIcon(transparencyButton, symbol: "circle.lefthalf.filled", active: transparent, help: transparent ? "恢复背景" : "透明背景")
            setIcon(closeButton, symbol: "xmark", active: false, help: "关闭自选弹框")
            window?.invalidateCursorRects(for: self)
        }
        private func setIcon(_ button: NSButton, symbol: String, active: Bool, help: String) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
            button.contentTintColor = NSColor(active ? Palette.purple : Palette.muted)
            button.toolTip = help
            button.setAccessibilityLabel(help)
        }
        override func layout() {
            super.layout()
            grip.frame = NSRect(x: 6, y: (bounds.height - 9) / 2, width: 9, height: 9)
            title.frame = NSRect(x: 21, y: (bounds.height - 15) / 2, width: max(bounds.width - 100, 0), height: 15)
            for (index, button) in [pinButton, transparencyButton, closeButton].enumerated() {
                button.frame = NSRect(x: bounds.width - 4 - CGFloat(3 - index) * 22, y: (bounds.height - 20) / 2, width: 20, height: 20)
            }
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            guard pinned else { return }
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            super.resetCursorRects()
            if pinned {
                addCursorRect(NSRect(x: 0, y: 0, width: max(bounds.width - 72, 0), height: bounds.height), cursor: .openHand)
            }
        }
        @objc private func togglePin() { pinAction?() }
        @objc private func toggleTransparency() { transparencyAction?() }
        @objc private func closePanel() { closeAction?() }
    }

    private final class PassthroughLabel: NSTextField {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    private final class PassthroughImage: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    private final class ToolbarButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
