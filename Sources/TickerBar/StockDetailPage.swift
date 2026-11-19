import SwiftUI
import MarketCore

enum DetailPeriod: String, CaseIterable, Identifiable {
    case minute = "分时", day = "日 K", week = "周 K", month = "月 K"
    var id: String { rawValue }
    var candlePeriod: CandlePeriod? {
        switch self { case .minute: return nil; case .day: return .day; case .week: return .week; case .month: return .month }
    }
}

struct StockDetailPage: View {
    @ObservedObject var store: MarketStore
    let symbol: String
    @State private var highlighted: CandleBar?
    private var isLeading: Bool { symbol == MarketStore.leadingSymbol }
    private var quote: Quote? { store.quotes[symbol] }
    private var adjustment: PriceAdjustment { store.effectiveAdjustment(for: symbol) }
    private var key: String { MarketStore.candleKey(symbol, store.detailPeriod.candlePeriod ?? .day, adjustment) }
    private var series: CandleSeries? { store.candleSeries[key] }
    private var request: String { symbol + "|" + store.detailPeriod.rawValue + "|" + adjustment.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            quoteSummary.padding(.vertical, 18)
            controls
            if store.detailPeriod == .minute || isLeading { minuteChart }
            else { candleChart }
        }.padding(.horizontal, 22).padding(.bottom, 16)
            .task(id: request) { highlighted = nil; await load() }
            .onChange(of: store.candleCount) { _ in highlighted = nil }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button { store.selected = nil } label: { Label("返回自选", systemImage: "chevron.left").font(.system(size: 12, weight: .medium)) }
                .buttonStyle(.plain).foregroundColor(Palette.purple)
            Rectangle().fill(Palette.line).frame(width: 1, height: 16)
            Text(store.menuName(symbol)).font(.system(size: 19, weight: .semibold))
            Text(isLeading ? "上证领先" : String(symbol.dropFirst(2))).font(.system(size: 12, design: .monospaced)).foregroundColor(Palette.muted)
            Spacer()
            Button { store.toggleMenuSymbol(symbol) } label: {
                Label(store.menuSymbols.contains(symbol) ? "从菜单栏移除" : "加入菜单栏轮播", systemImage: "menubar.rectangle").font(.system(size: 11))
            }.buttonStyle(.plain).foregroundColor(Palette.purple).disabled(store.menuSymbols == [symbol])
        }.frame(height: 42)
    }

    private var quoteSummary: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(quote?.priceText ?? "—").font(.system(size: 39, weight: .semibold, design: .rounded)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(MarketFormat.percent(quote?.percent)).font(.system(size: 16, weight: .semibold))
                        Text(quote.map { String(format: quote?.isFund == true ? "%+.3f" : "%+.2f", $0.change) } ?? "—").font(.system(size: 12))
                    }.monospacedDigit()
                }.foregroundColor(Palette.movement(quote?.percent))
                Text(quote.map { "行情时间 " + Self.formatTimestamp($0.timestamp) } ?? "行情获取中…")
                    .font(.system(size: 10)).foregroundColor(Palette.muted)
            }.frame(width: 290, alignment: .leading)
            if isLeading {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LeadingIndex.name + " · 上证领先指标").font(.system(size: 15, weight: .medium)).foregroundColor(.orange)
                    Text("展示东财上证分时图中的黄线数据，用于观察不按市值加权的市场走势。").font(.system(size: 12))
                    Text("涨跌以东财上证分时的昨收基准计算；仅提供分时，不提供独立 K 线或成交量。").font(.system(size: 11)).foregroundColor(Palette.muted)
                    Text(store.leadingStatus).font(.system(size: 11)).foregroundColor(store.leadingError ? .orange : Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 16) {
                metric("今开", price(quote?.open)); metric("昨收", price(quote?.previousClose))
                metric("最高", price(quote?.high)); metric("最低", price(quote?.low))
                metric("成交量", quote.map { MarketFormat.compact($0.volume) + "股" } ?? "—")
                metric("换手率", quote?.turnover.map { String(format: "%.2f%%", $0) } ?? "—")
                metric("市盈率", quote?.pe.map { String(format: "%.2f", $0) } ?? "—")
                metric("市场状态", store.sessionText)
            }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(isLeading ? [DetailPeriod.minute] : DetailPeriod.allCases) { period in
                Button { store.detailPeriod = period } label: {
                    Text(period.rawValue).font(.system(size: 13, weight: .medium))
                        .foregroundColor(store.detailPeriod == period ? Palette.purple : Palette.muted)
                        .padding(.horizontal, 17).padding(.vertical, 9)
                        .background(store.detailPeriod == period ? Palette.purple.opacity(0.08) : .clear).cornerRadius(7)
                }.buttonStyle(.plain)
            }
            Spacer()
            if store.detailPeriod != .minute && !isLeading {
                Picker("显示数量", selection: $store.candleCount) {
                    ForEach([60, 120, 250], id: \.self) { Text("\($0) 根").tag($0) }
                }.labelsHidden().frame(width: 100)
                if quote?.kind != "ZS" && quote?.isFund != true {
                    Picker("复权方式", selection: $store.priceAdjustment) {
                        ForEach(PriceAdjustment.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 105)
                }
            }
            if store.candleLoading.contains(key) && store.detailPeriod != .minute { ProgressView().controlSize(.small) }
            IconButton(icon: "arrow.clockwise", help: "更新当前图表") { Task { await load(force: true) } }
        }.frame(height: 48)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var minuteChart: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                Text("当日分时").foregroundColor(Palette.ink)
                Text(isLeading ? "● " + LeadingIndex.name : "● 价格").foregroundColor(isLeading ? .orange : Palette.movement(quote?.percent))
                if !isLeading && quote?.kind != "ZS" { Text("● 均价").foregroundColor(.orange) }
                Spacer()
                if store.trendErrors.contains(symbol) { Text("分时更新失败，可点击刷新重试").foregroundColor(.orange) }
            }.font(.system(size: 11)).padding(.top, 15)
            TrendChart(series: store.minutes[symbol], quote: quote, detailed: true, lineColor: isLeading ? .orange : nil).frame(maxHeight: .infinity)
            HStack { Text("09:30"); Spacer(); Text("11:30 / 13:00"); Spacer(); Text("15:00") }
                .font(.system(size: 10)).foregroundColor(Palette.muted)
            HStack { Text("鼠标移到曲线上查看分时价格"); Spacer(); Text("虚线为昨收价") }
                .font(.system(size: 10)).foregroundColor(Palette.muted)
        }
    }

    private var candleChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let series = series {
                candleReadout(highlighted ?? series.bars.last)
                HStack(spacing: 20) {
                    Text("MA5").foregroundColor(.orange)
                    Text("MA10").foregroundColor(.blue)
                    Text("MA20").foregroundColor(Palette.purple)
                    Spacer()
                    Text(series.adjustment.title + " · " + "\(min(store.candleCount, series.bars.count)) 根 K 线").foregroundColor(Palette.muted)
                }.font(.system(size: 10))
                CandleChart(series: series, count: store.candleCount, isFund: quote?.isFund == true, highlighted: $highlighted)
                    .id(key + "|\(store.candleCount)")
                    .frame(maxHeight: .infinity)
                HStack {
                    Text(store.candleErrors[key] == nil ? "悬停查看历史开高低收 · 红涨绿跌" : "更新失败，当前显示已缓存的 K 线").foregroundColor(store.candleErrors[key] == nil ? Palette.muted : .orange)
                    Spacer()
                    Text("图表获取于 " + series.fetchedAt.formatted(date: .omitted, time: .shortened)).foregroundColor(Palette.muted)
                }.font(.system(size: 10))
            } else {
                VStack(spacing: 14) {
                    if store.candleLoading.contains(key) { ProgressView(); Text("正在获取 K 线…") }
                    else {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 32, weight: .light))
                        Text(store.candleErrors[key] ?? "暂无 K 线数据")
                        Button("重新加载") { Task { await load(force: true) } }.buttonStyle(.bordered)
                    }
                }.font(.system(size: 13)).foregroundColor(Palette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(.top, 15)
    }

    private func candleReadout(_ bar: CandleBar?) -> some View {
        HStack(spacing: 20) {
            Text(bar?.date ?? "—").foregroundColor(Palette.ink)
            Text("开 " + price(bar?.open)); Text("高 " + price(bar?.high))
            Text("低 " + price(bar?.low)); Text("收 " + price(bar?.close))
            Text("成交量 " + (bar.map { MarketFormat.compact($0.volume) + "股" } ?? "—"))
            Spacer()
        }.font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.muted)
    }
    private func price(_ value: Double?) -> String { value.map { String(format: quote?.isFund == true ? "%.3f" : "%.2f", $0) } ?? "—" }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundColor(Palette.muted)
            Text(value).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
    private func load(force: Bool = false) async {
        if isLeading { await store.fetchLeading(force: force) }
        else if let period = store.detailPeriod.candlePeriod { await store.fetchCandles(symbol, period: period, adjustment: adjustment, force: force) }
        else { await store.fetchMinutes(symbol, force: force) }
    }
    private static func formatTimestamp(_ text: String) -> String {
        guard text.count == 14 else { return "—" }
        return String(text.prefix(8)) + " " + String(text.suffix(6).prefix(2)) + ":" + String(text.suffix(4).prefix(2)) + ":" + String(text.suffix(2))
    }
}
