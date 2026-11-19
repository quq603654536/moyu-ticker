import Foundation

public enum CandlePeriod: String, Codable, CaseIterable {
    case day, week, month
}

public enum PriceAdjustment: String, Codable, CaseIterable, Identifiable {
    case forward = "qfq", none = ""
    public var id: String { rawValue }
    public var title: String { self == .forward ? "前复权" : "不复权" }
}

public struct CandleBar: Codable, Equatable, Identifiable {
    public let date: String
    public let open: Double
    public let close: Double
    public let high: Double
    public let low: Double
    public let volume: Double
    public var id: String { date }
}

public struct CandleSeries: Codable, Equatable {
    public let symbol: String
    public let period: CandlePeriod
    public let adjustment: PriceAdjustment
    public let bars: [CandleBar]
    public let fetchedAt: Date

    /// Calculate against the complete history, before slicing the display range.
    public func movingAverage(length: Int) -> [Double?] {
        guard length > 0 else { return Array(repeating: nil, count: bars.count) }
        var sum = 0.0
        return bars.indices.map { index in
            sum += bars[index].close
            if index >= length { sum -= bars[index - length].close }
            return index + 1 >= length ? sum / Double(length) : nil
        }
    }
}

public extension MarketParser {
    static func candles(_ data: Data, symbol: String, period: CandlePeriod, adjustment: PriceAdjustment) throws -> CandleSeries {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? NSNumber)?.intValue == 0,
              let all = root["data"] as? [String: Any], let stock = all[symbol] as? [String: Any] else { throw MarketError.invalidResponse }
        let adjustedKey = adjustment.rawValue + period.rawValue
        let key = stock[adjustedKey] is [[Any]] ? adjustedKey : period.rawValue
        guard let rows = stock[key] as? [[Any]] else { throw MarketError.noData }
        let actualAdjustment: PriceAdjustment = key.hasPrefix("qfq") ? .forward : .none
        let snapshot = (stock["qt"] as? [String: Any])?[symbol] as? [String]
        let volumeScale = tencentVolumeScale(symbol: symbol, kind: tencentKind(snapshot))
        var unique: [String: CandleBar] = [:]
        for row in rows {
            guard row.count >= 6, let date = row[0] as? String,
                  date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { continue }
            func number(_ index: Int) -> Double? {
                let result = (row[index] as? String).flatMap(Double.init) ?? (row[index] as? NSNumber)?.doubleValue
                return result.flatMap { $0.isFinite ? $0 : nil }
            }
            guard let open = number(1), let close = number(2), let high = number(3), let low = number(4),
                  let volume = number(5), volume >= 0, high >= max(open, close), low <= min(open, close) else { continue }
            // Forward adjustment can legitimately make old prices negative after
            // accumulated cash dividends. Preserve those candles and their dates.
            unique[date] = CandleBar(date: date, open: open, close: close, high: high, low: low, volume: volume * volumeScale)
        }
        let bars = unique.values.sorted { $0.date < $1.date }
        guard !bars.isEmpty else { throw MarketError.noData }
        return CandleSeries(symbol: symbol, period: period, adjustment: actualAdjustment, bars: bars, fetchedAt: Date())
    }
}

public extension MarketService {
    func candles(_ symbol: String, period: CandlePeriod, adjustment: PriceAdjustment) async throws -> CandleSeries {
        return try await tracked("腾讯 · K线") {
            guard symbol.range(of: #"^(sh|sz|bj)\d{6}$"#, options: .regularExpression) != nil else { throw MarketError.invalidResponse }
            let parameter = "\(symbol),\(period.rawValue),,,320,\(adjustment.rawValue)"
            var url = URLComponents(string: "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get")!
            url.queryItems = [.init(name: "param", value: parameter)]
            return try MarketParser.candles(try await get(url.url!.absoluteString), symbol: symbol, period: period, adjustment: adjustment)
        }
    }
}
