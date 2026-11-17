import SwiftUI
import MarketCore

struct CandleChart: View {
    let series: CandleSeries
    let count: Int
    let isFund: Bool
    @Binding var highlighted: CandleBar?
    @State private var hoverIndex: Int?

    private var start: Int { max(0, series.bars.count - count) }
    private var bars: [CandleBar] { Array(series.bars.dropFirst(start)) }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in draw(context, size: size) }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let position):
                        let width = max(geometry.size.width - 62, 1)
                        guard position.x >= 0, position.x < width, !bars.isEmpty else {
                            hoverIndex = nil; highlighted = nil; return
                        }
                        let index = min(max(Int(position.x / width * CGFloat(bars.count)), 0), bars.count - 1)
                        if hoverIndex != index { hoverIndex = index; highlighted = bars[index] }
                    case .ended: hoverIndex = nil; highlighted = nil
                    }
                }
                .accessibilityLabel("\(series.period.rawValue) 蜡烛图，\(bars.count) 根 K 线，含均线和成交量")
        }
    }

    private func draw(_ context: GraphicsContext, size: CGSize) {
        let visible = bars
        guard !visible.isEmpty else { return }
        let averages = [series.movingAverage(length: 5), series.movingAverage(length: 10), series.movingAverage(length: 20)]
        var values = visible.flatMap { [$0.low, $0.high] }
        for average in averages { values += average.dropFirst(start).compactMap { $0 } }
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 1
        let padding = max((highest - lowest) * 0.08, max(abs(highest), 1) * 0.001)
        let low = lowest - padding
        let high = highest + padding
        let width = max(size.width - 62, 1)
        let priceTop: CGFloat = 10
        let priceHeight = max(size.height * 0.72 - 18, 1)
        let volumeTop = priceTop + priceHeight + 28
        let volumeHeight = max(size.height - volumeTop - 25, 8)
        let maxVolume = max(visible.map(\.volume).max() ?? 0, 1)
        let step = width / CGFloat(visible.count)
        let candleWidth = min(max(step * 0.65, 1), 14)
        func x(_ index: Int) -> CGFloat { (CGFloat(index) + 0.5) * step }
        func y(_ price: Double) -> CGFloat { priceTop + CGFloat((high - price) / (high - low)) * priceHeight }
        func label(_ value: String, at point: CGPoint, anchor: UnitPoint = .leading, color: Color = Palette.muted) {
            context.draw(Text(value).font(.system(size: 10, design: .monospaced)).foregroundColor(color), at: point, anchor: anchor)
        }
        for level in 0..<5 {
            let lineY = priceTop + priceHeight * CGFloat(level) / 4
            var line = Path()
            line.move(to: .init(x: 0, y: lineY)); line.addLine(to: .init(x: width, y: lineY))
            context.stroke(line, with: .color(Palette.line), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
            let price = high - (high - low) * Double(level) / 4
            label(String(format: isFund ? "%.3f" : "%.2f", price), at: .init(x: width + 8, y: lineY))
        }
        for (index, bar) in visible.enumerated() {
            let color = bar.close >= bar.open ? Palette.red : Palette.green
            var wick = Path()
            wick.move(to: .init(x: x(index), y: y(bar.high)))
            wick.addLine(to: .init(x: x(index), y: y(bar.low)))
            context.stroke(wick, with: .color(color), lineWidth: 1)
            let body = CGRect(x: x(index) - candleWidth / 2, y: min(y(bar.open), y(bar.close)), width: candleWidth, height: max(abs(y(bar.close) - y(bar.open)), 1))
            context.fill(Path(body), with: .color(bar.close >= bar.open ? .white : color))
            context.stroke(Path(body), with: .color(color), lineWidth: 1)
            if bar.volume > 0 {
                let volume = CGFloat(bar.volume / maxVolume) * volumeHeight
                let volumeRect = CGRect(x: x(index) - candleWidth / 2, y: volumeTop + volumeHeight - volume, width: candleWidth, height: max(volume, 0.5))
                context.fill(Path(volumeRect), with: .color(color.opacity(0.70)))
            }
        }
        let colors: [Color] = [.orange, .blue, Palette.purple]
        for (number, average) in averages.enumerated() {
            var line = Path()
            var started = false
            for index in visible.indices {
                guard let value = average[start + index] else { started = false; continue }
                let position = CGPoint(x: x(index), y: y(value))
                if !started { line.move(to: position); started = true } else { line.addLine(to: position) }
            }
            context.stroke(line, with: .color(colors[number]), lineWidth: 1.15)
        }
        label("成交量", at: .init(x: 0, y: volumeTop - 12))
        label(MarketFormat.compact(maxVolume) + "股", at: .init(x: size.width - 2, y: volumeTop), anchor: .trailing)
        for index in Set([0, visible.count / 2, visible.count - 1]).sorted() {
            let date = visible[index].date
            let text = series.period == .day ? String(date.suffix(5)) : String(date.prefix(7))
            let location = min(max(x(index), 26), max(width - 26, 26))
            label(text, at: .init(x: location, y: size.height - 8), anchor: .center)
        }
        if let index = hoverIndex, visible.indices.contains(index) {
            let bar = visible[index]
            var crosshair = Path()
            crosshair.move(to: .init(x: x(index), y: priceTop)); crosshair.addLine(to: .init(x: x(index), y: volumeTop + volumeHeight))
            crosshair.move(to: .init(x: 0, y: y(bar.close))); crosshair.addLine(to: .init(x: width, y: y(bar.close)))
            context.stroke(crosshair, with: .color(Palette.purple.opacity(0.65)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            let box = CGRect(x: min(max(x(index) - 43, 0), max(width - 86, 0)), y: size.height - 19, width: 86, height: 20)
            context.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Palette.purple))
            label(bar.date, at: .init(x: box.midX, y: box.midY), anchor: .center, color: .white)
        }
    }
}
