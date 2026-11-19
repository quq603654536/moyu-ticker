import SwiftUI
import MarketCore

struct DashboardView: View {
    @ObservedObject var store: MarketStore
    let openWindow: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                titlebar
                if let symbol = store.selected { StockDetailPage(store: store, symbol: symbol).id(symbol) }
                else if store.showOverview { overview } else { watchlist }
                footer
            }.background(.white)
        }
        .foregroundColor(Palette.ink)
        .background(.white)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $store.showSearch) { SearchView(store: store) }
        .sheet(isPresented: $store.showSettings) { SettingsView(store: store) }
        .onChange(of: store.group) { _ in
            store.selected = nil
            Task { for item in store.visibleItems { await store.fetchMinutes(item.symbol) } }
        }
    }

    private var titlebar: some View {
        HStack(spacing: 8) {
            Text("摸鱼盯盘").font(.system(size: 14, weight: .semibold))
            Text("/  A 股行情").font(.system(size: 11)).foregroundColor(Palette.muted)
            Spacer()
            Circle().fill(store.isStale ? Color.orange : Palette.green).frame(width: 5, height: 5)
            Text(store.paused ? "已暂停更新" : store.sessionText).font(.system(size: 10)).foregroundColor(Palette.muted)
            Rectangle().fill(Palette.line).frame(width: 1, height: 12).padding(.horizontal, 8)
            IconButton(icon: "arrow.clockwise", help: "刷新行情 ⌘R") { Task { await store.refresh() } }
                .disabled(store.refreshing)
            IconButton(icon: store.pinned ? "pin.fill" : "pin", help: "固定面板，点击外部时保持展开", active: store.pinned) { store.pinned.toggle() }
            IconButton(icon: "arrow.up.left.and.arrow.down.right", help: "原尺寸查看完整行情") { openWindow() }
            IconButton(icon: "xmark", help: "收起面板") { close() }
        }.padding(.horizontal, 20).frame(height: 48)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button { store.showOverview = false; store.selected = nil } label: {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 23, weight: .medium))
                    .foregroundColor(Palette.purple).frame(width: 45, height: 46)
                    .background(Palette.purple.opacity(0.11)).cornerRadius(13)
            }.buttonStyle(.plain).help("自选行情").padding(.top, 18).padding(.bottom, 20)
            sideButton("list.bullet.rectangle", label: "自选行情", active: !store.showOverview) { store.showOverview = false; store.selected = nil }
            sideButton("square.grid.2x2", label: "市场概览", active: store.showOverview) { store.showOverview = true; store.selected = nil }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 17).padding(.vertical, 18)
            breadthSummary
            Spacer(minLength: 14)
            sideButton("gearshape", label: "设置", active: store.showSettings) { store.showSettings = true }
            sideButton("power", label: "退出摸鱼盯盘", active: false) { NSApp.terminate(nil) }
            Text("轻巧 · 专注").font(.system(size: 8)).foregroundColor(Palette.muted.opacity(0.7)).padding(.vertical, 15)
        }.frame(width: 76).background(Palette.canvas)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }
    private func sideButton(_ icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
                .foregroundColor(active ? Palette.purple : Palette.muted)
                .frame(width: 44, height: 43)
                .background(active ? Palette.purple.opacity(0.07) : .clear).cornerRadius(10)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private var breadthSummary: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                Rectangle().fill(Palette.red).frame(width: 25, height: 14)
                Rectangle().fill(Palette.green).frame(width: 11, height: 14)
            }.cornerRadius(2).padding(.bottom, 2)
            summary("上涨", store.breadth.map { String($0.up) } ?? "—", Palette.red)
            summary("平盘", store.breadth.map { String($0.flat) } ?? "—", Palette.purple)
            summary("下跌", store.breadth.map { String($0.down) } ?? "—", Palette.green)
            summary("成交额", MarketFormat.compact(store.breadth?.amount), Palette.ink)
            Text("沪深 A 股").font(.system(size: 9)).foregroundColor(Palette.muted)
            if store.breadthError {
                Button(store.breadth == nil ? "统计暂不可用" : "统计为缓存") { Task { await store.fetchBreadth() } }
                    .buttonStyle(.plain).font(.system(size: 8)).foregroundColor(.orange).help("点击重试市场统计")
            }
            if store.breadth?.delayed == true { Text("延时统计").font(.system(size: 8)).foregroundColor(.orange) }
            if let date = store.breadth?.fetchedAt {
                Text(date, style: .time).font(.system(size: 8)).foregroundColor(Palette.muted)
                if Date().timeIntervalSince(date) > 180 { Text("缓存").font(.system(size: 8)).foregroundColor(.orange) }
            }
        }
    }
    private func summary(_ name: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.system(size: 11)).foregroundColor(Palette.muted)
            Text(value).font(.system(size: name == "成交额" ? 12 : 17, weight: .medium, design: .rounded)).monospacedDigit().foregroundColor(color).lineLimit(1).minimumScaleFactor(0.65)
        }.padding(.horizontal, 4)
    }

    private var indexStrip: some View {
        HStack(spacing: 12) {
            ForEach(Array(MarketStore.indices.enumerated()), id: \.element) { i, symbol in
                IndexCard(name: MarketStore.indexNames[i], quote: store.quotes[symbol], active: store.selected == symbol, stale: symbol == MarketStore.leadingSymbol && store.quoteIsStale(symbol))
                    .onTapGesture { store.openDetails(symbol) }
                    .contextMenu { Button(store.menuSymbols.contains(symbol) ? "从菜单栏移除" : "加入菜单栏轮播") { store.toggleMenuSymbol(symbol) }
                        .disabled(store.menuSymbols == [symbol]) }
                    .help(symbol == MarketStore.leadingSymbol ? store.leadingStatus : "点击查看分时详情；右键可加入菜单栏轮播")
            }
        }.padding(.horizontal, 20).padding(.bottom, 16)
    }
    private var watchlist: some View {
        VStack(spacing: 0) {
            indexStrip
            HStack(alignment: .center, spacing: 24) {
                ForEach(StockGroup.allCases) { group in
                    Button { store.group = group; store.filter = "" } label: {
                        VStack(spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(group.rawValue).font(.system(size: 17, weight: store.group == group ? .semibold : .regular))
                                Text("\(store.items.filter { $0.group == group }.count)").font(.system(size: 10, weight: .medium))
                            }
                            Rectangle().fill(store.group == group ? Palette.purple : .clear).frame(height: 2).cornerRadius(1)
                        }.foregroundColor(store.group == group ? Palette.purple : Palette.muted)
                    }.buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
                if !store.filter.isEmpty {
                    TextField("筛选当前分组", text: $store.filter).textFieldStyle(.roundedBorder).frame(width: 150)
                }
                Menu {
                    ForEach(SortField.allCases, id: \.self) { field in Button(field.rawValue) { store.sortBy(field) } }
                } label: {
                    Label(store.sort.rawValue, systemImage: "arrow.up.arrow.down").font(.system(size: 11)).foregroundColor(Palette.muted)
                }.menuStyle(.borderlessButton).fixedSize().help("排序方式")
                Button { store.showSearch = true } label: {
                    Label("添加自选", systemImage: "plus").font(.system(size: 11, weight: .medium))
                        .foregroundColor(Palette.purple).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Palette.purple.opacity(0.08)).cornerRadius(7)
                }.buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
            }.padding(.horizontal, 22).frame(height: 42)
            GeometryReader { geo in
                VStack(spacing: 0) {
                    tableHeader(width: geo.size.width)
                    if store.visibleItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star").font(.system(size: 30, weight: .light)).foregroundColor(Palette.purple.opacity(0.5))
                            Text("把值得关注的公司放在这里").font(.system(size: 14)).foregroundColor(Palette.muted)
                            Button("添加第一只自选股") { store.showSearch = true }.buttonStyle(.bordered)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.visibleItems) { item in
                                    StockRow(store: store, item: item, width: geo.size.width)
                                }
                            }
                        }
                    }
                }
            }.padding(.horizontal, 12)
        }
    }

    private func tableHeader(width: CGFloat) -> some View {
        let contentWidth = max(width - 28, 0)
        return HStack(spacing: 0) {
            Text("名称 / 代码").frame(width: contentWidth * 0.34, alignment: .leading)
            header("价格", .price, width: contentWidth * 0.16)
            Text("分时走势").font(.system(size: 10)).frame(width: contentWidth * 0.32)
            header("当日涨跌", .change, width: contentWidth * 0.18)
        }.font(.system(size: 12, weight: .medium)).foregroundColor(Palette.muted)
            .padding(.horizontal, 14).frame(height: 42).background(Palette.canvas)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
    private func header(_ label: String, _ field: SortField, width: CGFloat) -> some View {
        Button { store.sortBy(field) } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: store.sort == field ? (store.ascending ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill") : "chevron.up.chevron.down")
                    .font(.system(size: 7)).foregroundColor(store.sort == field ? Palette.purple : Palette.muted.opacity(0.4))
            }.frame(width: width, height: 42)
        }.buttonStyle(.plain).foregroundColor(store.sort == field ? Palette.purple : Palette.muted)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                indexStrip.padding(.horizontal, -20)
                Text("市场概览").font(.system(size: 22, weight: .semibold))
                Text("五大指数与上涨领先 · 点击查看当日分时").font(.system(size: 12)).foregroundColor(Palette.muted)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) {
                    ForEach(Array(MarketStore.indices.enumerated()), id: \.element) { i, symbol in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(MarketStore.indexNames[i]).font(.system(size: 14, weight: .medium))
                                Spacer()
                                Text(MarketFormat.percent(store.quotes[symbol]?.percent)).foregroundColor(Palette.movement(store.quotes[symbol]?.percent))
                            }
                            TrendChart(series: store.minutes[symbol], quote: store.quotes[symbol], detailed: true, lineColor: symbol == MarketStore.leadingSymbol ? .orange : nil).frame(height: 120)
                            HStack { Text("09:30"); Spacer(); Text("11:30 / 13:00"); Spacer(); Text("15:00") }.font(.system(size: 9)).foregroundColor(Palette.muted)
                        }.padding(18).background(Palette.canvas).cornerRadius(12)
                            .task { await store.fetchMinutes(symbol) }
                            .onTapGesture { store.openDetails(symbol) }
                    }
                }
            }.padding(20)
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.error != nil ? .orange : Palette.green).frame(width: 4, height: 4)
            if store.refreshing { Text("正在更新…") }
            else if let error = store.error { Text(error).lineLimit(1).help(error) }
            else if let date = store.latestQuoteDate {
                Text("行情时间 \(Self.quoteTime(date))")
            } else { Text("连接行情服务中…") }
            Spacer()
            Text("\(store.refreshInterval) 秒刷新 · 腾讯行情 / 东方财富").lineLimit(1)
            Text("· 右键管理自选").padding(.leading, 4)
        }.font(.system(size: 9)).foregroundColor(Palette.muted)
            .padding(.horizontal, 20).frame(height: 32)
            .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }
    private static func quoteTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct IndexCard: View {
    let name: String
    let quote: Quote?
    let active: Bool
    var stale = false
    var body: some View {
        let color = Palette.movement(quote?.percent)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(name).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: stale ? "clock" : (quote?.percent ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 9, weight: .semibold)).opacity(0.55)
            }
            Text(quote?.priceText ?? "—").font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 5) {
                Text(quote.map { String(format: "%+.2f", $0.change) } ?? "—")
                Spacer(minLength: 0)
                Text(MarketFormat.percent(quote?.percent))
            }.font(.system(size: 11, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.foregroundColor(color).padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [color.opacity(0.12), color.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(12).overlay { RoundedRectangle(cornerRadius: 12).stroke(active ? Palette.purple.opacity(0.55) : color.opacity(0.04), lineWidth: 1) }.opacity(stale ? 0.65 : 1)
    }
}

struct StockRow: View {
    @ObservedObject var store: MarketStore
    let item: WatchItem
    let width: CGFloat
    @State private var hovered = false
    private var quote: Quote? { store.quotes[item.symbol] }
    var body: some View {
        let contentWidth = max(width - 28, 0)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(quote?.name ?? item.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(item.symbol.dropFirst(2))).font(.system(size: 11, design: .monospaced)).foregroundColor(Palette.muted)
                    if item.holding { Text("持仓").font(.system(size: 9, weight: .medium)).foregroundColor(Color.blue).padding(.horizontal, 4).padding(.vertical, 2).background(Color.blue.opacity(0.07)).cornerRadius(3) }
                    if store.menuSymbols.contains(item.symbol) { Image(systemName: "menubar.rectangle").font(.system(size: 9)).foregroundColor(Palette.purple) }
                }
            }.frame(width: contentWidth * 0.34, alignment: .leading)
            Text(quote?.priceText ?? "—").font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundColor(Palette.movement(quote?.percent)).frame(width: contentWidth * 0.16)
            TrendChart(series: store.minutes[item.symbol], quote: quote).frame(width: max(contentWidth * 0.32 - 24, 30), height: 48)
                .padding(.horizontal, 12).help(store.trendErrors.contains(item.symbol) ? "分时暂不可用，稍后自动重试" : "查看当日分时走势")
            ChangeBadge(value: quote?.percent).padding(.horizontal, 10)
                .frame(maxWidth: 160).frame(width: contentWidth * 0.18)
        }.font(.system(size: 15, design: .rounded)).monospacedDigit()
            .padding(.horizontal, 14).frame(height: 76)
            .background(store.selected == item.symbol ? Palette.purple.opacity(0.055) : hovered ? Palette.canvas : .white)
            .contentShape(Rectangle()).onTapGesture { store.openDetails(item.symbol) }
            .onHover { hovered = $0 }
            .overlay(alignment: .bottom) { Palette.line.opacity(0.7).frame(height: 1) }
            .contextMenu {
                Button("查看股票详情") { store.openDetails(item.symbol) }
                Button(store.menuSymbols.contains(item.symbol) ? "从菜单栏移除" : "加入菜单栏轮播") { store.toggleMenuSymbol(item.symbol) }
                    .disabled(store.menuSymbols == [item.symbol])
                Button(item.holding ? "取消持仓标记" : "标记为持仓") { store.update(item.symbol) { $0.holding.toggle() } }
                Menu("移到分组") {
                    ForEach(StockGroup.allCases) { group in Button(group.rawValue) { store.update(item.symbol) { $0.group = group } } }
                }
                Divider()
                Button("上移") { store.move(item.symbol, by: -1) }
                Button("下移") { store.move(item.symbol, by: 1) }
                Divider()
                Button("从自选移除", role: .destructive) { store.remove(item.symbol) }
            }
    }
}
