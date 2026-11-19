import SwiftUI
import MarketCore

struct HoverPreview: View {
    @ObservedObject var store: MarketStore
    let expand: () -> Void
    var selectStock: ((String) -> Void)? = nil
    static func size(for itemCount: Int) -> NSSize {
        NSSize(width: 250, height: CGFloat(min(max(itemCount, 1), 8)) * 16 + 130)
    }
    var body: some View {
        let size = Self.size(for: store.items.count)
        VStack(spacing: 0) {
            HoverToolbar(pinned: store.hoverPinned, transparent: store.hoverTransparent,
                pin: { store.hoverPinned.toggle() }, transparency: { store.hoverTransparent.toggle() }, close: {
                    store.hoverPinned = false
                    store.previewVisible = false
                })
                .frame(maxWidth: .infinity).frame(height: 22).padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(MarketStore.indices.enumerated()), id: \.element) { index, symbol in
                    quoteLine(name: MarketStore.indexNames[index], symbol: symbol, height: 14)
                }
            }.padding(.bottom, 8)
            if store.items.isEmpty {
                Text("暂无自选股").font(.system(size: 10)).foregroundColor(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { item in
                            quoteLine(name: store.quotes[item.symbol]?.name ?? item.name, symbol: item.symbol, height: 16)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
        }.padding(6)
            .frame(width: size.width, height: size.height).background(store.hoverTransparent ? Color.clear : .white)
            .foregroundColor(Palette.ink).environment(\.colorScheme, .light)
    }

    private func quoteLine(name: String, symbol: String, height: CGFloat) -> some View {
        let quote = store.quotes[symbol]
        return HStack(spacing: 3) {
            Text(name + "：").lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(quote?.priceText ?? "—").monospacedDigit()
                .frame(width: 54, alignment: .trailing)
                .foregroundColor(Palette.movement(quote?.percent))
            Text("(" + MarketFormat.percent(quote?.percent) + ")").monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: 58, alignment: .trailing)
                .foregroundColor(Palette.movement(quote?.percent))
        }.font(.system(size: 10)).frame(height: height)
            .contentShape(Rectangle()).help(symbol == MarketStore.leadingSymbol ? store.leadingStatus : name)
            .opacity(symbol == MarketStore.leadingSymbol && store.quoteIsStale(symbol) ? 0.6 : 1)
            .onTapGesture {
                if let selectStock = selectStock { selectStock(symbol) } else { expand() }
            }
    }
}

/// A tracking-area owner can observe the native status button without replacing
/// its hit testing, left/right clicks, or system menu-bar accessibility.
@MainActor final class MouseTrackingOwner: NSObject {
    var changed: (Bool) -> Void
    private weak var view: NSView?
    private var area: NSTrackingArea?
    init(view: NSView, changed: @escaping (Bool) -> Void) {
        self.view = view
        self.changed = changed
        super.init()
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        self.area = area
        view.addTrackingArea(area)
    }
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { changed(true) }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { changed(false) }
}

@MainActor final class HoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: HoverPreview.size(for: 0)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
    func show(below button: NSStatusBarButton, itemCount: Int, reposition: Bool = true) {
        guard let statusWindow = button.window else { return }
        let size = HoverPreview.size(for: itemCount)
        let sizeChanged = contentView?.frame.size != size
        // A pinned window is positioned by the user. Quote refreshes must not
        // resize, reorder or reset its frame while the Window Server drags it.
        if isVisible && !reposition && !sizeChanged { return }
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        if sizeChanged { setContentSize(size) }
        if reposition {
            let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = statusWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let x = min(max(anchor.midX - frame.width / 2, screen.minX + 8), screen.maxX - frame.width - 8)
            setFrameOrigin(NSPoint(x: x, y: anchor.minY - frame.height - 6))
        } else if sizeChanged { setFrameTopLeftPoint(topLeft) }
        if !isVisible { orderFrontRegardless() }
    }
}
