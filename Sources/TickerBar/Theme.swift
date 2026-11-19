import SwiftUI
import MarketCore

enum Palette {
    static let purple = Color(red: 0.44, green: 0.27, blue: 0.98)
    static let ink = Color(red: 0.16, green: 0.18, blue: 0.24)
    static let muted = Color(red: 0.54, green: 0.57, blue: 0.64)
    static let line = Color(red: 0.91, green: 0.92, blue: 0.94)
    static let green = Color(red: 0.12, green: 0.65, blue: 0.32)
    static let red = Color(red: 0.91, green: 0.29, blue: 0.32)
    static let canvas = Color(red: 0.98, green: 0.98, blue: 0.99)
    static func movement(_ value: Double?) -> Color {
        guard let value = value else { return muted }
        return value > 0 ? red : value < 0 ? green : muted
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundColor(active ? Palette.purple : Palette.muted)
                .frame(width: 30, height: 30)
                .background(active ? Palette.purple.opacity(0.10) : Color.clear)
                .cornerRadius(8)
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct ChangeBadge: View {
    let value: Double?
    var body: some View {
        Text(MarketFormat.percent(value))
            .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundColor(value == nil ? Palette.muted : .white)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(Palette.movement(value).opacity(value == nil ? 0.08 : 0.83))
            .cornerRadius(4)
    }
}

struct TrendChart: View {
    let series: MinuteSeries?
    let quote: Quote?
    var detailed = false
    var lineColor: Color? = nil
    @State private var hoverX: CGFloat?

    var validSeries: MinuteSeries? { series.flatMap { $0.matches(quote) ? $0 : nil } }
    var body: some View {
        GeometryReader { geo in
            if let series = validSeries, !series.points.isEmpty {
                let points = series.points
                let baseline = quote?.previousClose ?? points[0].price
                let showAverage = quote?.kind != "ZS"
                let values = points.flatMap { [$0.price, showAverage ? ($0.average ?? $0.price) : $0.price] } + [baseline]
                let minPrice = values.min() ?? baseline
                let maxPrice = values.max() ?? baseline
                let padding = max((maxPrice - minPrice) * 0.12, maxPrice * 0.0005)
                let low = minPrice - padding
                let high = maxPrice + padding
                let width = geo.size.width
                let height = geo.size.height
                let y: (Double) -> CGFloat = { CGFloat(1 - ($0 - low) / max(high - low, 0.00001)) * height }
                let x: (MinutePoint) -> CGFloat = { CGFloat($0.minute / 240) * width }
                ZStack(alignment: .topLeading) {
                    if detailed {
                        ForEach(0..<5) { i in
                            Path { p in p.move(to: .init(x: 0, y: height * CGFloat(i) / 4)); p.addLine(to: .init(x: width, y: height * CGFloat(i) / 4)) }
                                .stroke(Palette.line, style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                        }
                    }
                    Path { p in p.move(to: .init(x: 0, y: y(baseline))); p.addLine(to: .init(x: width, y: y(baseline))) }
                        .stroke(Palette.muted.opacity(0.65), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                    Path { path in
                        for (i, point) in points.enumerated() {
                            let pos = CGPoint(x: x(point), y: y(point.price))
                            if i == 0 { path.move(to: pos) } else { path.addLine(to: pos) }
                        }
                        if let first = points.first, let last = points.last {
                            path.addLine(to: .init(x: x(last), y: height))
                            path.addLine(to: .init(x: x(first), y: height)); path.closeSubpath()
                        }
                    }.fill(LinearGradient(colors: [(lineColor ?? Palette.movement(quote?.percent)).opacity(detailed ? 0.10 : 0.04), .clear], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        var started = false
                        for point in points {
                            guard showAverage, let average = point.average else { continue }
                            let pos = CGPoint(x: x(point), y: y(average))
                            if !started { path.move(to: pos); started = true } else { path.addLine(to: pos) }
                        }
                    }.stroke(Color.orange.opacity(0.75), lineWidth: detailed ? 1.2 : 0.9)
                    Path { path in
                        for (i, point) in points.enumerated() {
                            let pos = CGPoint(x: x(point), y: y(point.price))
                            if i == 0 { path.move(to: pos) } else { path.addLine(to: pos) }
                        }
                    }.stroke(lineColor ?? Palette.movement(quote?.percent), style: StrokeStyle(lineWidth: detailed ? 1.6 : 1.15, lineJoin: .round))
                    if detailed, let hx = hoverX, let point = points.min(by: { abs(x($0) - hx) < abs(x($1) - hx) }) {
                        Path { p in p.move(to: .init(x: x(point), y: 0)); p.addLine(to: .init(x: x(point), y: height)) }
                            .stroke(Palette.purple.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(Palette.purple).frame(width: 6, height: 6).offset(x: x(point) - 3, y: y(point.price) - 3)
                        Text("\(String(point.time.prefix(2))):\(String(point.time.suffix(2)))  \(String(format: quote?.isFund == true ? "%.3f" : "%.2f", point.price))")
                            .font(.system(size: 10, weight: .medium)).foregroundColor(Palette.ink)
                            .padding(5).background(.white).cornerRadius(4)
                            .offset(x: min(max(x(point) - 40, 0), max(width - 110, 0)), y: 0)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase { case .active(let point): hoverX = point.x; case .ended: hoverX = nil }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "waveform.path").font(.system(size: detailed ? 24 : 15))
                    if detailed { Text("暂无当日分时数据").font(.system(size: 11)) }
                }.foregroundColor(Palette.muted.opacity(0.55)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
