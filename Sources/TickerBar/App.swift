import Cocoa
import SwiftUI
import Combine
import MarketCore

@main struct TickerBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = MarketStore()
    private var statusItem: NSStatusItem!
    private let hoverPanel = HoverPanel()
    private var buttonTracking: MouseTrackingOwner?
    private var previewTracking: MouseTrackingOwner?
    private var hoverWork: DispatchWorkItem?
    private var buttonHovered = false
    private var previewHovered = false
    private var window: NSWindow?
    private var subscribers = Set<AnyCancellable>()
    private var keyMonitor: Any?
    private var heartbeat: Timer?
    private let menuRotation = MenuBarRotation()
    private var menuQuoteView: MenuBarQuoteView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let position = CommandLine.arguments.firstIndex(of: "--verify"), CommandLine.arguments.indices.contains(position + 1) {
            let directory = CommandLine.arguments[position + 1]
            Task { await AppVerification.run(output: directory) }
            return
        }
        // A second launch should reveal the existing app instead of creating a
        // second background process and a duplicate menu-bar item.
        if let bundleID = Bundle.main.bundleIdentifier {
            let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                DistributedNotificationCenter.default().post(name: .init("com.tickerbar.reveal"), object: nil)
                NSApp.terminate(nil)
                return
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "TickerBar.Status"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let quoteView = MenuBarQuoteView(frame: button.bounds)
            button.addSubview(quoteView)
            menuQuoteView = quoteView
        }
        hoverPanel.contentView = NSHostingView(rootView: HoverPreview(store: store, expand: { [weak self] in self?.showWindow() }, selectStock: { [weak self] symbol in
            self?.store.openDetails(symbol)
            self?.showWindow()
        }).cornerRadius(12))
        if let button = statusItem.button {
            buttonTracking = MouseTrackingOwner(view: button) { [weak self] inside in self?.statusHoverChanged(inside) }
        }
        if let view = hoverPanel.contentView {
            previewTracking = MouseTrackingOwner(view: view) { [weak self] inside in
                guard let self = self else { return }
                self.previewHovered = inside
                if inside { self.hoverWork?.cancel() } else { self.schedulePreviewClose() }
            }
        }
        store.$pinned.sink { [weak self] pinned in self?.window?.level = pinned ? .floating : .normal }.store(in: &subscribers)
        store.$hoverPinned.sink { [weak self] pinned in
            guard let self = self else { return }
            self.hoverPanel.level = pinned ? .floating : .popUpMenu
            if pinned { self.hoverWork?.cancel() } else { self.schedulePreviewClose() }
        }.store(in: &subscribers)
        store.$hoverTransparent.sink { [weak self] transparent in
            self?.hoverPanel.hasShadow = !transparent
            self?.hoverPanel.invalidateShadow()
        }.store(in: &subscribers)
        store.objectWillChange.debounce(for: .milliseconds(80), scheduler: RunLoop.main).sink { [weak self] _ in
            guard let self = self else { return }
            self.updateStatus()
            if self.store.previewVisible, let button = self.statusItem.button {
                self.hoverPanel.show(below: button, itemCount: self.store.items.count, reposition: !self.store.hoverPinned)
            } else {
                self.previewHovered = false
                self.hoverPanel.orderOut(nil)
            }
        }.store(in: &subscribers)
        menuRotation.onChange = { [weak self] in self?.updateStatus() }
        store.$menuSymbols.removeDuplicates().dropFirst().sink { [weak self] symbols in
            // Published values arrive before the store setter has completed.
            DispatchQueue.main.async { [weak self] in self?.menuRotation.configure(symbols) }
        }.store(in: &subscribers)
        menuRotation.configure(store.menuSymbols)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.updateStatus() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reveal), name: .init("com.tickerbar.reveal"), object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "r": Task { @MainActor in await self.store.refresh() }; return nil
                case "f": self.showDashboardWindow(); self.store.showSearch = true; return nil
                case ",": self.settings(); return nil
                case "q": NSApp.terminate(nil); return nil
                case "w": NSApp.keyWindow?.performClose(nil); return nil
                default: break
                }
            }
            if event.keyCode == 53, !self.store.showSettings, !self.store.showSearch {
                if self.store.selected != nil { self.store.selected = nil }
                else if self.window?.isKeyWindow == true { self.window?.close() }
                return nil
            }
            return event
        }
        updateStatus()
        store.start()
        if ProcessInfo.processInfo.arguments.contains("--window") {
            DispatchQueue.main.async { [weak self] in self?.showWindow() }
        } else if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showWindow() }
        }
    }
    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        let symbol = menuRotation.symbol
        let quote = store.quotes[symbol]
        let name = store.menuName(symbol)
        let shortName: String
        if let index = MarketStore.indices.firstIndex(of: symbol) {
            shortName = ["上证", "深证", "创业板", "科创50", "沪深300", "中证1000"][index]
        } else { shortName = String(name.prefix(6)) }
        let text: String
        if let quote = quote {
            text = "\(shortName) \(store.menuShowPrice ? quote.priceText + " " : "")\(MarketFormat.percent(quote.percent))\(store.isStale ? " ·" : "")"
        } else { text = "\(shortName) —" }
        let color: NSColor
        if let q = quote, !store.isStale {
            color = q.percent > 0 ? NSColor(calibratedRed: 0.92, green: 0.28, blue: 0.3, alpha: 1) : q.percent < 0 ? NSColor(calibratedRed: 0.13, green: 0.68, blue: 0.33, alpha: 1) : .labelColor
        } else { color = .secondaryLabelColor }
        // Reserve the widest selected quote so other menu-bar items stay still.
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let width = store.menuSymbols.map { candidate -> CGFloat in
            let candidateQuote = store.quotes[candidate]
            let candidateName: String
            if let i = MarketStore.indices.firstIndex(of: candidate) {
                candidateName = ["上证", "深证", "创业板", "科创50", "沪深300", "中证1000"][i]
            } else { candidateName = String(store.menuName(candidate).prefix(6)) }
            let title = candidateQuote.map { "\(candidateName) \(store.menuShowPrice ? $0.priceText + " " : "")\(MarketFormat.percent($0.percent))\(store.isStale ? " ·" : "")" } ?? "\(candidateName) —"
            return NSAttributedString(string: title, attributes: [.font: font]).size().width
        }.max() ?? 0
        statusItem.length = ceil(width) + 38
        button.title = ""
        button.image = nil
        menuQuoteView?.frame = button.bounds
        menuQuoteView?.layoutSubtreeIfNeeded()
        menuQuoteView?.display(symbol: symbol, title: NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        button.setAccessibilityLabel("盯盘行情 " + text)
        button.toolTip = nil
    }
    @objc private func statusClicked() {
        dismissPreview()
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "打开独立窗口", action: #selector(showWindow), keyEquivalent: "")
            menu.addItem(withTitle: "原尺寸显示完整行情", action: #selector(showDashboardWindow), keyEquivalent: "")
            menu.addItem(withTitle: "刷新行情", action: #selector(refresh), keyEquivalent: "r")
            menu.addItem(.separator())
            menu.addItem(withTitle: "偏好设置…", action: #selector(settings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出盯盘", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { showWindow() }
    }
    private func statusHoverChanged(_ inside: Bool) {
        buttonHovered = inside
        hoverWork?.cancel()
        if inside {
            if store.hoverPinned && hoverPanel.isVisible { return }
            guard !store.showSettings, !store.showSearch else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.buttonHovered,
                      let button = self.statusItem.button else { return }
                self.store.previewVisible = true
                self.hoverPanel.show(below: button, itemCount: self.store.items.count)
                // Hover previews never activate the app or take keyboard focus.
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        } else { schedulePreviewClose() }
    }
    private func schedulePreviewClose() {
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.buttonHovered, !self.previewHovered, !self.store.hoverPinned else { return }
            self.store.previewVisible = false
            self.hoverPanel.orderOut(nil)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }
    private func dismissPreview() {
        hoverWork?.cancel()
        guard !store.hoverPinned else { return }
        previewHovered = false
        store.previewVisible = false
        hoverPanel.orderOut(nil)
    }
    @objc private func reveal() { showWindow() }
    @objc private func woke() { Task { await store.refresh() } }
    @objc private func refresh() { Task { await store.refresh() } }
    @objc private func settings() { showDashboardWindow(); store.showSettings = true }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showWindow() {
        presentDashboard(at: ScaledDashboardView.initialSize)
    }
    @objc private func showDashboardWindow() {
        presentDashboard(at: ScaledDashboardView.canvasSize, centered: true)
    }
    private func presentDashboard(at size: NSSize, centered: Bool = false) {
        dismissPreview()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "盯盘 · A 股行情"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = store.pinned ? .floating : .normal
            w.contentMinSize = ScaledDashboardView.minimumSize
            w.contentMaxSize = ScaledDashboardView.canvasSize
            w.contentAspectRatio = ScaledDashboardView.canvasSize
            w.contentView = NSHostingView(rootView: ScaledDashboardView(store: store, openWindow: { [weak self] in self?.showDashboardWindow() }, close: { [weak self] in self?.window?.close() }))
            w.setFrameAutosaveName("TickerBar.ScaledDashboard")
            window = w
        }
        if let window = window {
            let button = statusItem.button
            let screen = (centered && window.isVisible ? window.screen : nil) ?? button?.window?.screen ?? NSScreen.main
            let visible = screen?.visibleFrame
            let chromeHeight = window.frame.height - (window.contentView?.frame.height ?? 0)
            let scale = visible.map { min(1, ($0.width - 16) / size.width, ($0.height - chromeHeight - 16) / size.height) } ?? 1
            window.setContentSize(NSSize(width: size.width * scale, height: size.height * scale))
            if centered, let visible = visible {
                window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                              y: visible.midY - window.frame.height / 2))
            } else if let button = button, let statusWindow = button.window, let visible = visible {
                let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
                let left = min(max(anchor.minX, visible.minX + 8), visible.maxX - window.frame.width - 8)
                let top = min(anchor.minY - 2, visible.maxY - 2)
                let bottom = max(visible.minY + 8, top - window.frame.height)
                window.setFrameOrigin(NSPoint(x: left, y: bottom))
            } else { window.center() }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        heartbeat?.invalidate()
        menuRotation.stop()
    }
}
