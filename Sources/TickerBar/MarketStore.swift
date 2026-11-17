import SwiftUI
import Combine
import MarketCore

enum StockGroup: String, Codable, CaseIterable, Identifiable {
    case value = "价投", watch = "观察股", etf = "ETF"
    var id: String { rawValue }
}

struct WatchItem: Codable, Identifiable {
    let symbol: String
    var name: String
    var group: StockGroup
    var holding: Bool = false
    var note: String = ""
    var id: String { symbol }
}

enum SortField: String, CaseIterable { case manual = "默认", price = "价格", change = "当日涨跌" }

@MainActor final class MarketStore: ObservableObject {
    static let indices = ["sh000001", "sz399001", "sz399006", "sh000688", "sh000300", "sh000852"]
    static let indexNames = ["上证指数", "深证成指", "创业板指", "科创50", "沪深300", "中证1000"]
    static let defaults: [WatchItem] = [
        .init(symbol: "sh588010", name: "科创新材料ETF博时", group: .value, holding: true),
        .init(symbol: "sh603156", name: "养元饮品", group: .value),
        .init(symbol: "sz001337", name: "四川黄金", group: .value),
        .init(symbol: "sh601288", name: "农业银行", group: .value),
        .init(symbol: "sz002842", name: "翔鹭钨业", group: .value),
        .init(symbol: "sh600487", name: "亨通光电", group: .value),
        .init(symbol: "sh601606", name: "长城军工", group: .value),
        .init(symbol: "sh600519", name: "贵州茅台", group: .watch),
        .init(symbol: "sz300750", name: "宁德时代", group: .watch),
        .init(symbol: "sh510300", name: "沪深300ETF", group: .etf),
        .init(symbol: "sh510500", name: "中证500ETF", group: .etf)
    ]
    @Published var items: [WatchItem] { didSet { save(items, "watchlist") } }
    @Published var quotes: [String: Quote] = [:]
    @Published var minutes: [String: MinuteSeries] = [:]
    @Published var breadth: MarketBreadth?
    @Published var breadthError = false
    @Published var group: StockGroup = .value
    @Published var sort: SortField = .manual
    @Published var ascending = false
    @Published var selected: String?
    @Published var detailPeriod: DetailPeriod = .minute
    @Published var priceAdjustment: PriceAdjustment = .forward
    @Published var candleCount = 60
    @Published var candleSeries: [String: CandleSeries] = [:]
    @Published var candleLoading = Set<String>()
    @Published var candleErrors: [String: String] = [:]
    @Published var refreshing = false
    @Published var lastSuccess: Date?
    @Published var error: String?
    @Published var trendErrors: Set<String> = []
    @Published var pinned = false
    @Published var showSettings = false
    @Published var showSearch = false
    @Published var showOverview = false
    @Published var previewVisible = false
    @Published var hoverPinned = false
    @Published var hoverTransparent: Bool { didSet { preferences.set(hoverTransparent, forKey: "hoverTransparent") } }
    @Published var filter = ""
    @Published var refreshInterval: Int { didSet { preferences.set(refreshInterval, forKey: "refreshInterval"); if started { scheduleTimer() } } }
    @Published private(set) var menuSymbols: [String] { didSet { preferences.set(menuSymbols, forKey: "menuSymbols") } }
    @Published var menuShowPrice: Bool { didSet { preferences.set(menuShowPrice, forKey: "menuShowPrice") } }
    @Published var paused = false
    private let service: MarketService
    private let preferences: UserDefaults
    private var timer: Timer?
    private var minuteUpdated: [String: Date] = [:]
    private var trendInFlight = Set<String>()
    private var started = false
    private var breadthAttempt: Date?
    private var candleAttempt: [String: Date] = [:]

    init(preferences defaults: UserDefaults = .standard, service: MarketService = MarketService()) {
        self.service = service
        preferences = defaults
        items = Self.read([WatchItem].self, "watchlist", defaults) ?? Self.defaults
        refreshInterval = [5, 10, 15, 30, 60].contains(defaults.integer(forKey: "refreshInterval")) ? defaults.integer(forKey: "refreshInterval") : 15
        let savedMenuSymbol = defaults.string(forKey: "menuSymbol") ?? "sh000001"
        let savedSymbols = defaults.stringArray(forKey: "menuSymbols") ?? [savedMenuSymbol]
        var seen = Set<String>()
        let validSymbols = savedSymbols.map { $0 == "sh000905" ? "sh000852" : $0 }.filter {
            $0.range(of: #"^(sh|sz|bj)\d{6}$"#, options: .regularExpression) != nil && seen.insert($0).inserted
        }
        menuSymbols = validSymbols.isEmpty ? [Self.indices[0]] : validSymbols
        menuShowPrice = defaults.object(forKey: "menuShowPrice") as? Bool ?? true
        hoverTransparent = defaults.bool(forKey: "hoverTransparent")
        quotes = Self.read([String: Quote].self, "quotes", defaults) ?? [:]
        minutes = Self.read([String: MinuteSeries].self, "minutes", defaults) ?? [:]
        breadth = Self.read(MarketBreadth.self, "breadth", defaults)
        lastSuccess = defaults.object(forKey: "lastSuccess") as? Date
        candleSeries = Self.read([String: CandleSeries].self, "candles", defaults) ?? [:]
    }

    private static func read<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { preferences.set(data, forKey: key) }
    }
    func setMenuSymbol(_ symbol: String, enabled: Bool) {
        guard symbol.range(of: #"^(sh|sz|bj)\d{6}$"#, options: .regularExpression) != nil else { return }
        if enabled {
            if !menuSymbols.contains(symbol) { menuSymbols.append(symbol) }
        } else if menuSymbols.count > 1 {
            menuSymbols.removeAll { $0 == symbol }
        }
    }
    func toggleMenuSymbol(_ symbol: String) {
        setMenuSymbol(symbol, enabled: !menuSymbols.contains(symbol))
    }
    func menuName(_ symbol: String) -> String {
        if let i = Self.indices.firstIndex(of: symbol) { return Self.indexNames[i] }
        return quotes[symbol]?.name ?? items.first { $0.symbol == symbol }?.name ?? symbol
    }
    var visibleItems: [WatchItem] {
        let matches = items.filter { $0.group == group && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.symbol.contains(filter)) }
        guard sort != .manual else { return matches }
        func value(_ item: WatchItem) -> Double? {
            guard let q = quotes[item.symbol] else { return nil }
            switch sort {
            case .manual: return nil
            case .price: return q.price
            case .change: return q.percent
            }
        }
        return matches.sorted {
            let a = value($0), b = value($1)
            if a == b { return $0.symbol < $1.symbol }
            guard let a = a else { return false }
            guard let b = b else { return true }
            return ascending ? a < b : a > b
        }
    }
    var isStale: Bool { error != nil || lastSuccess.map { Date().timeIntervalSince($0) > Double(refreshInterval * 3 + 15) } ?? true }
    var latestQuoteDate: Date? { quotes.values.compactMap(\.quoteDate).max() }
    var sessionText: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        guard let date = latestQuoteDate, calendar.isDate(date, inSameDayAs: now) else { return "最近交易日" }
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if [1, 7].contains(calendar.component(.weekday, from: now)) { return "休市" }
        if (570...690).contains(minute) || (780...900).contains(minute) { return "交易中" }
        if (691..<780).contains(minute) { return "午间休市" }
        return minute < 570 ? "盘前" : "已收盘"
    }

    func start() {
        guard !started else { return }
        started = true
        scheduleTimer()
        Task { await refresh() }
    }
    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            guard let store = self else { return }
            Task { @MainActor in
                guard !store.paused else { return }
                await store.refresh()
            }
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let symbols = Array(Set(Self.indices + items.map(\.symbol) + menuSymbols))
        do {
            let result = try await service.quotes(symbols)
            for quote in result { quotes[quote.symbol] = quote }
            let returned = Set(result.map(\.symbol))
            let missing = symbols.filter { !returned.contains($0) }
            error = missing.isEmpty ? nil : "部分证券暂无行情：" + missing.joined(separator: "、")
            lastSuccess = Date()
            save(quotes, "quotes")
            preferences.set(lastSuccess, forKey: "lastSuccess")
        } catch {
            self.error = "行情更新失败，已保留上次数据 · " + error.localizedDescription
        }
        await withTaskGroup(of: Void.self) { tasks in
            if breadthAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true {
                tasks.addTask { await self.fetchBreadth() }
            }
            // URLSession limits connections per host; cache minute data for 60s.
            let trendSymbols = visibleItems.map(\.symbol) + (showOverview ? Self.indices : [])
            for symbol in Set(trendSymbols) { tasks.addTask { await self.fetchMinutes(symbol) } }
            if let selected = selected, !visibleItems.contains(where: { $0.symbol == selected }) {
                tasks.addTask { await self.fetchMinutes(selected) }
            }
            if let selected = selected, let period = detailPeriod.candlePeriod {
                tasks.addTask { await self.fetchCandles(selected, period: period, adjustment: self.effectiveAdjustment(for: selected)) }
            }
        }
        save(minutes, "minutes")
    }
    func fetchBreadth() async {
        breadthAttempt = Date()
        do {
            let result = try await service.breadth()
            breadth = result
            breadthError = false
            save(result, "breadth")
        } catch { breadthError = true }
    }
    func fetchMinutes(_ symbol: String, force: Bool = false) async {
        guard !trendInFlight.contains(symbol) else { return }
        guard force || minuteUpdated[symbol].map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        trendInFlight.insert(symbol)
        defer { trendInFlight.remove(symbol) }
        do {
            minutes[symbol] = try await service.minutes(symbol)
            minuteUpdated[symbol] = Date()
            trendErrors.remove(symbol)
        } catch { trendErrors.insert(symbol) }
    }
    func select(_ symbol: String) {
        if selected == symbol { selected = nil } else { openDetails(symbol) }
    }
    func openDetails(_ symbol: String) {
        detailPeriod = .minute
        selected = symbol
        Task { await fetchMinutes(symbol) }
    }
    func effectiveAdjustment(for symbol: String) -> PriceAdjustment {
        quotes[symbol]?.kind == "ZS" || quotes[symbol]?.isFund == true ? .none : priceAdjustment
    }
    static func candleKey(_ symbol: String, _ period: CandlePeriod, _ adjustment: PriceAdjustment) -> String {
        "\(symbol)|\(period.rawValue)|\(adjustment.rawValue)"
    }
    func fetchCandles(_ symbol: String, period: CandlePeriod, adjustment: PriceAdjustment, force: Bool = false) async {
        let key = Self.candleKey(symbol, period, adjustment)
        guard !candleLoading.contains(key) else { return }
        guard force || candleSeries[key].map({ Date().timeIntervalSince($0.fetchedAt) >= 60 }) ?? true else { return }
        guard force || candleAttempt[key].map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        candleAttempt[key] = Date()
        candleLoading.insert(key)
        defer { candleLoading.remove(key) }
        do {
            candleSeries[key] = try await service.candles(symbol, period: period, adjustment: adjustment)
            candleErrors.removeValue(forKey: key)
            save(candleSeries, "candles")
        } catch {
            if Task.isCancelled { candleAttempt.removeValue(forKey: key) }
            else { candleErrors[key] = "K 线更新失败，请稍后重试" }
        }
    }
    func sortBy(_ field: SortField) {
        if sort == field { ascending.toggle() } else { sort = field; ascending = false }
    }
    func add(_ result: SearchResult, group: StockGroup) {
        guard !items.contains(where: { $0.symbol == result.symbol }) else { return }
        items.append(.init(symbol: result.symbol, name: result.name, group: group))
        self.group = group
        Task { await refresh() }
    }
    func remove(_ symbol: String) {
        items.removeAll { $0.symbol == symbol }
        if selected == symbol { selected = nil }
        let remaining = menuSymbols.filter { $0 != symbol }
        menuSymbols = remaining.isEmpty ? [Self.indices[0]] : remaining
    }
    func update(_ symbol: String, _ body: (inout WatchItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.symbol == symbol }) else { return }
        body(&items[i])
    }
    func move(_ symbol: String, by offset: Int) {
        let groupItems = items.filter { $0.group == group }
        guard let i = groupItems.firstIndex(where: { $0.symbol == symbol }), groupItems.indices.contains(i + offset),
              let source = items.firstIndex(where: { $0.symbol == symbol }),
              let dest = items.firstIndex(where: { $0.symbol == groupItems[i + offset].symbol }) else { return }
        items.swapAt(source, dest)
        sort = .manual
    }
    func search(_ query: String) async throws -> [SearchResult] { try await service.search(query) }
}
