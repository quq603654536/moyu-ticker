import Foundation

/// Provider-defined reference curve, not a separately tradable security.
public enum LeadingIndex {
    public static let symbol = "sh000001-leading"
    public static let name = "上涨领先"
}

public struct LeadingIndexSnapshot: Codable {
    public let quote: Quote
    public let series: MinuteSeries
    public let delayed: Bool
    public let fetchedAt: Date
}

public extension MarketParser {
    static func leadingIndex(_ data: Data, delayed: Bool = false) throws -> LeadingIndexSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["rc"] as? NSNumber)?.intValue == 0,
              let detail = root["data"] as? [String: Any], detail["code"] as? String == "000001",
              (detail["market"] as? NSNumber)?.intValue == 1,
              let baseline = ((detail["prePrice"] as? NSNumber) ?? (detail["preClose"] as? NSNumber))?.doubleValue,
              baseline.isFinite, baseline > 0, let rows = detail["trends"] as? [String] else { throw MarketError.invalidResponse }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        var values: [String: Double] = [:]
        for row in rows {
            let fields = row.components(separatedBy: ",")
            // Eastmoney's chart maps f58 (the eighth column) to its yellow curve.
            // Never substitute the blue index price or aggregate turnover/volume.
            guard fields.count >= 8, fields[0].count == 16, formatter.date(from: fields[0]) != nil,
                  let value = Double(fields[7]), value.isFinite, value > 0 else { continue }
            values[fields[0]] = value
        }
        guard let timestamp = values.keys.max(), let last = values[timestamp] else { throw MarketError.noData }
        let day = String(timestamp.prefix(10))
        let times = values.keys.filter { $0.hasPrefix(day) }.sorted()
        let points = times.compactMap { time -> MinutePoint? in
            guard let price = values[time] else { return nil }
            return MinutePoint(time: time.suffix(5).replacingOccurrences(of: ":", with: ""), price: price, average: nil)
        }
        guard let first = points.first else { throw MarketError.noData }
        let date = day.replacingOccurrences(of: "-", with: "")
        let quoteTime = date + timestamp.suffix(5).replacingOccurrences(of: ":", with: "") + "00"
        let quote = Quote(symbol: LeadingIndex.symbol, name: LeadingIndex.name, code: "LEADING", price: last,
                          previousClose: baseline, open: first.price, high: points.map(\.price).max() ?? last,
                          low: points.map(\.price).min() ?? last, change: last - baseline,
                          percent: (last / baseline - 1) * 100, volume: 0, amount: 0,
                          marketCap: nil, turnover: nil, pe: nil, ytd: nil, timestamp: quoteTime, kind: "ZS")
        return LeadingIndexSnapshot(quote: quote, series: MinuteSeries(date: date, points: points), delayed: delayed, fetchedAt: Date())
    }
}

public extension MarketService {
    func leadingIndex() async throws -> LeadingIndexSnapshot {
        try await tracked("东财 · 上证黄线") {
            let path = "/api/qt/stock/trends2/get?secid=1.000001&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14,f17&fields2=f51,f52,f53,f54,f55,f56,f57,f58&ndays=1&iscr=0&iscca=0"
            var lastError: Error = MarketError.noData
            for host in ["push2.eastmoney.com", "push2delay.eastmoney.com"] {
                do {
                    let data = try await get("https://" + host + path, timeout: 5, retry: false)
                    return try MarketParser.leadingIndex(data, delayed: host.contains("delay"))
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                    lastError = error
                }
            }
            throw lastError
        }
    }
}
