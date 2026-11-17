import AppKit
import SwiftUI
import MarketCore

/// Developer-only checks using a separate preferences suite. Does not change the
/// user's watchlist, login items, menu-bar placement, or application settings.
@MainActor enum AppVerification {
    private struct Failure: Error, CustomStringConvertible { let description: String }
    private static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(description: message) }
    }
    static func run(output: String) async {
        let suite = "com.tickerbar.verification.\(ProcessInfo.processInfo.processIdentifier)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        do {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let log = RequestLog(directory: directory.appendingPathComponent("diagnostic-logs"))
            let store = MarketStore(preferences: preferences, service: MarketService(log: log))
            try await verifyMenuAnimation(directory: directory)
            let panel = HoverPanel()
            try check(!panel.canBecomeKey && !panel.canBecomeMain, "Hover preview must not steal keyboard focus")
            let tracker = MouseTrackingOwner(view: NSView()) { _ in }
            try check(tracker.responds(to: NSSelectorFromString("mouseEntered:")) && tracker.responds(to: NSSelectorFromString("mouseExited:")), "Native hover selectors are registered correctly")
            await store.refresh()
            try check(store.error == nil, "Live quote refresh: \(store.error ?? "")")
            try check(store.quotes.count >= 17, "All initial indices and watchlist quotes")
            try check(store.visibleItems.count == 7, "Initial value group has 7 rows")
            try check(store.minutes["sh601288"]?.matches(store.quotes["sh601288"]) == true, "Intraday chart has current-day points")
            let root = DashboardView(store: store, openWindow: {}, close: {})
            try await snapshot(root, width: 1240, height: 800, file: directory.appendingPathComponent("main.png"))
            let scaledSize = ScaledDashboardView.initialSize
            try await snapshot(ScaledDashboardView(store: store, openWindow: {}, close: {}), width: scaledSize.width, height: scaledSize.height, file: directory.appendingPathComponent("scaled-dashboard.png"))
            let hoverSize = HoverPreview.size(for: store.items.count)
            try await snapshot(HoverPreview(store: store, expand: {}), width: hoverSize.width, height: hoverSize.height, file: directory.appendingPathComponent("hover.png"))
            store.hoverPinned = true
            try await snapshot(HoverPreview(store: store, expand: {}), width: hoverSize.width, height: hoverSize.height, file: directory.appendingPathComponent("hover-pinned.png"))
            store.hoverTransparent = true
            let transparentFile = directory.appendingPathComponent("hover-transparent.png")
            try await snapshot(HoverPreview(store: store, expand: {}), width: hoverSize.width, height: hoverSize.height, file: transparentFile)
            let bitmap = NSBitmapImageRep(data: try Data(contentsOf: transparentFile))!
            var transparentPixels = 0
            var samples = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 12) {
                    if let color = bitmap.colorAt(x: x, y: y) {
                        samples += 1
                        if color.alphaComponent < 0.05 { transparentPixels += 1 }
                    }
                }
            }
            try check(samples > 0 && Double(transparentPixels) / Double(samples) > 0.5, "Transparent hover background has real alpha, not faded text")
            store.hoverPinned = false
            store.hoverTransparent = false
            store.select("sh601288")
            try check(store.selected == "sh601288", "Row selection opens details")
            try await snapshot(root, width: 1240, height: 800, file: directory.appendingPathComponent("detail.png"))
            for (period, detail) in [(CandlePeriod.day, DetailPeriod.day), (.week, .week), (.month, .month)] {
                store.detailPeriod = detail
                await store.fetchCandles("sh601288", period: period, adjustment: .forward)
                let key = MarketStore.candleKey("sh601288", period, .forward)
                try check(store.candleSeries[key]?.bars.isEmpty == false && store.candleErrors[key] == nil, "Live \(period.rawValue) candle history")
                try await snapshot(root, width: 1240, height: 800, file: directory.appendingPathComponent("detail-\(period.rawValue).png"))
            }
            store.detailPeriod = .day
            store.priceAdjustment = .none
            await store.fetchCandles("sh601288", period: .day, adjustment: .none)
            let rawKey = MarketStore.candleKey("sh601288", .day, .none)
            try check(store.candleSeries[rawKey]?.adjustment == PriceAdjustment.none, "Live unadjusted candle history")
            try await snapshot(root, width: 1240, height: 800, file: directory.appendingPathComponent("detail-unadjusted.png"))
            store.select("sh601288")
            try check(store.selected == nil, "Selecting a row twice closes details")
            store.sortBy(.change)
            let values = store.visibleItems.compactMap { store.quotes[$0.symbol]?.percent }
            try check(values == values.sorted(by: >), "Descending percentage sorting")
            store.sortBy(.change)
            let ascending = store.visibleItems.compactMap { store.quotes[$0.symbol]?.percent }
            try check(ascending == ascending.sorted(), "Ascending percentage sorting")
            store.update("sh601288") { $0.note = "长期观察"; $0.holding = true }
            store.setMenuSymbol("sh601288", enabled: true)
            store.setMenuSymbol("sz399001", enabled: true)
            store.setMenuSymbol("sh601288", enabled: true)
            try check(store.menuSymbols == ["sh000001", "sh601288", "sz399001"], "Multiple menu selections retain order and prevent duplicates")
            store.menuShowPrice = false
            store.refreshInterval = 30
            let restored = MarketStore(preferences: preferences)
            try check(restored.items.first { $0.symbol == "sh601288" }?.note == "长期观察", "Note survives reload")
            try check(restored.items.first { $0.symbol == "sh601288" }?.holding == true, "Holding marker survives reload")
            try check(restored.menuSymbols == ["sh000001", "sh601288", "sz399001"] && !restored.menuShowPrice && restored.refreshInterval == 30, "Menu-bar preferences survive reload")
            let rotation = MenuBarRotation()
            defer { rotation.stop() }
            rotation.configure(store.menuSymbols)
            try check(rotation.symbol == "sh000001", "Menu rotation starts at first selection")
            try await Task.sleep(nanoseconds: 3_200_000_000)
            try check(rotation.symbol == "sh601288", "Menu rotates to second selection after three seconds")
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try check(rotation.symbol == "sz399001", "Menu rotates through all selected symbols")
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try check(rotation.symbol == "sh000001", "Menu rotation wraps to first selection")
            rotation.configure(["sh601288"])
            try await Task.sleep(nanoseconds: 3_100_000_000)
            try check(rotation.symbol == "sh601288", "One menu selection remains fixed")
            store.setMenuSymbol("sz399001", enabled: false)
            store.setMenuSymbol("sh000001", enabled: false)
            store.setMenuSymbol("sh601288", enabled: false)
            try check(store.menuSymbols == ["sh601288"], "Cannot uncheck last menu selection")
            store.remove("sh601288")
            try check(store.menuSymbols == ["sh000001"], "Removing final selected stock restores default index")
            // Restore the stock for subsequent watchlist checks.
            store.items = restored.items
            preferences.removeObject(forKey: "menuSymbols")
            preferences.set("sh000905", forKey: "menuSymbol")
            let migrated = MarketStore(preferences: preferences)
            try check(migrated.menuSymbols == ["sh000852"], "Legacy single selection migrates with index replacement")
            store.setMenuSymbol("sh601288", enabled: true)
            try await snapshot(MenuSelectionView(store: store), width: 300, height: 380, file: directory.appendingPathComponent("menu-selection.png"))
            try check(!restored.quotes.isEmpty && !restored.minutes.isEmpty, "Offline quote and trend cache survives reload")
            try check(!restored.candleSeries.isEmpty, "K-line cache survives reload for offline viewing")
            store.sort = .manual
            store.move("sh601288", by: -1)
            try check(store.visibleItems[2].symbol == "sh601288", "Move watchlist row")
            store.update("sh601288") { $0.group = .watch }
            try check(!store.visibleItems.contains { $0.symbol == "sh601288" }, "Move stock between groups")
            store.group = .watch
            try check(store.visibleItems.contains { $0.symbol == "sh601288" }, "Destination group contains moved stock")
            let results = try await store.search("中国平安")
            guard let result = results.first(where: { $0.symbol == "sh601318" }) else { throw Failure(description: "Chinese stock search") }
            let oldCount = store.items.count
            store.add(result, group: .watch)
            try check(store.items.count == oldCount + 1, "Add searched stock")
            store.add(result, group: .watch)
            try check(store.items.count == oldCount + 1, "Prevent duplicate stock")
            store.remove(result.symbol)
            try check(store.items.count == oldCount, "Remove watched stock")
            store.showOverview = true
            for symbol in MarketStore.indices { await store.fetchMinutes(symbol) }
            try await snapshot(root, width: 1240, height: 800, file: directory.appendingPathComponent("overview.png"))
            try await snapshot(SettingsView(store: store), width: 512, height: 610, file: directory.appendingPathComponent("settings.png"))
            try await snapshot(RequestDiagnosticsView(log: log), width: 570, height: 480, file: directory.appendingPathComponent("request-diagnostics.png"))
            try "PASS: pinned/transparent hover, navigation, intraday and daily/weekly/monthly K-lines, adjustment, persistence; 15 rendered views; animated menu quote transitions\n".write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
            print("PASS: application integration and rendered previews at \(output)")
            NSApp.terminate(nil)
        } catch {
            let message = "FAIL: \(error)\n"
            try? message.write(toFile: output + "/result.txt", atomically: true, encoding: .utf8)
            fputs(message, stderr)
            Darwin.exit(1)
        }
    }
    private static func verifyMenuAnimation(directory: URL) async throws {
        let view = MenuBarQuoteView(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        func title(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.systemRed])
        }
        view.display(symbol: "sh000001", title: title("上证 3602.07 -0.01%"))
        try check(!view.isAnimating, "Initial menu quote appears immediately")
        try check(view.hitTest(NSPoint(x: 40, y: 12)) == nil, "Animated overlay preserves native clicks and hover tracking")
        view.display(symbol: "sh601288", title: title("农业银行 7.51 -1.05%"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try check(view.isAnimating, "Switching symbols starts a vertical animation")
        }
        view.display(symbol: "sh601288", title: title("农业银行 7.52 -0.92%"))
        try await Task.sleep(nanoseconds: 500_000_000)
        let labels = view.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }
        try check(!view.isAnimating && labels.count == 1, "Animation removes outgoing text")
        try check(labels.first?.stringValue == "农业银行 7.52 -0.92%", "Price refresh during animation keeps latest quote")
        view.display(symbol: "sz399001", title: title("深证 10764.88 +0.69%"))
        view.display(symbol: "sh000001", title: title("上证 3602.07 -0.01%"))
        try await Task.sleep(nanoseconds: 500_000_000)
        let finalLabels = view.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }
        try check(finalLabels.count == 1 && finalLabels.first?.stringValue == "上证 3602.07 -0.01%", "Interrupted scroll cannot leave overlapping rows")
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(description: "Create menu quote bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "Encode menu quote PNG") }
        try png.write(to: directory.appendingPathComponent("menu-quote.png"))
        window.contentView = nil
    }
    private static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat, file: URL) async throws {
        let host = NSHostingView(rootView: view.frame(width: width, height: height).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 350_000_000)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(description: "Create view bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(description: "Encode view PNG") }
        try png.write(to: file)
        window.contentView = nil
    }
}
