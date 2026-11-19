import Foundation
import CoreFoundation

public struct Quote: Codable, Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let code: String
    public let price: Double
    public let previousClose: Double
    public let open: Double
    public let high: Double
    public let low: Double
    public let change: Double
    public let percent: Double
    public let volume: Double
    public let amount: Double
    public let marketCap: Double?
    public let turnover: Double?
    public let pe: Double?
    public let ytd: Double?
    public let timestamp: String
    public let kind: String
    public var isFund: Bool { ["ETF", "LOF", "FUND"].contains(kind) || name.contains("ETF") }
    public var priceText: String { price > 0 ? String(format: isFund ? "%.3f" : "%.2f", price) : "—" }
    public var quoteDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: timestamp)
    }
}

public struct SearchResult: Identifiable, Equatable {
    public let symbol: String
    public let code: String
    public let name: String
    public let kind: String
    public var id: String { symbol }
}

public struct MinutePoint: Codable, Equatable {
    public let time: String
    public let price: Double
    public let average: Double?
    /// Trading-session minute, excluding the lunch break.
    public var minute: Double {
        guard time.count == 4, let hour = Int(time.prefix(2)), let min = Int(time.suffix(2)) else { return 0 }
        let total = hour * 60 + min
        return Double(max(0, minValue(240, total <= 690 ? total - 570 : total - 660)))
    }
}
private func minValue(_ a: Int, _ b: Int) -> Int { min(a, b) }

public struct MinuteSeries: Codable, Equatable {
    public let date: String
    public let points: [MinutePoint]
    public func matches(_ quote: Quote?) -> Bool { quote.map { $0.timestamp.hasPrefix(date) } ?? false }
}

public struct MarketBreadth: Codable {
    public let up: Int
    public let flat: Int
    public let down: Int
    public let amount: Double
    public let fetchedAt: Date
    public let delayed: Bool?
}

public enum MarketError: LocalizedError {
    case invalidResponse
    case noData
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "行情接口返回异常，请稍后重试"
        case .noData: return "暂未获取到行情，请检查网络后重试"
        }
    }
}

public enum MarketParser {
    static func tencentKind(_ fields: [String]?) -> String {
        fields?.dropFirst(51).first {
            $0 == "GP-A" || $0.hasPrefix("GP-A-") || ["ETF", "LOF", "ZS", "FUND"].contains($0)
        } ?? ""
    }

    // Tencent reports STAR Market volume in shares (including 689 CDRs),
    // while the other supported mainland securities use lots of 100 shares.
    // This convention applies to quotes, minute totals and K-line volume.
    static func tencentVolumeScale(symbol: String, kind: String) -> Double {
        kind == "GP-A-KCB" || symbol.hasPrefix("sh688") || symbol.hasPrefix("sh689") ? 1 : 100
    }

    public static func decode(_ data: Data) throws -> String {
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        guard let text = String(data: data, encoding: String.Encoding(rawValue: encoding)) ?? String(data: data, encoding: .utf8) else { throw MarketError.invalidResponse }
        return text
    }

    public static func quotes(_ text: String) -> [Quote] {
        let regex = try! NSRegularExpression(pattern: #"v_([a-z0-9]+)="([^"]*)""#)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let symbol = ns.substring(with: match.range(at: 1))
            let fields = ns.substring(with: match.range(at: 2)).components(separatedBy: "~")
            guard fields.count > 34, !fields[1].isEmpty, fields[2].count >= 5,
                  let price = Double(fields[3]), let previous = Double(fields[4]),
                  let change = Double(fields[31]), let percent = Double(fields[32]),
                  fields[30].count == 14 else { return nil }
            func number(_ i: Int) -> Double? { i < fields.count ? Double(fields[i]) : nil }
            // Extended performance fields follow the security-type marker, rather
            // than a guessed fixed offset (A shares / ETFs / indices may differ).
            let kind = tencentKind(fields)
            let marker = fields.indices.first { $0 > 50 && !kind.isEmpty && fields[$0] == kind }
            return Quote(symbol: symbol, name: fields[1], code: fields[2], price: price, previousClose: previous,
                         open: number(5) ?? 0, high: number(33) ?? 0, low: number(34) ?? 0,
                         change: change, percent: percent, volume: (number(36) ?? 0) * tencentVolumeScale(symbol: symbol, kind: kind),
                         amount: (number(37) ?? 0) * 10_000,
                         marketCap: number(45).flatMap { $0 > 0 ? $0 * 100_000_000 : nil },
                         turnover: number(38), pe: number(39), ytd: marker.flatMap { number($0 + 1) },
                         timestamp: fields[30], kind: kind)
        }
    }

    public static func search(_ text: String) -> [SearchResult] {
        guard let first = text.firstIndex(of: "\""), let last = text.lastIndex(of: "\""), first < last else { return [] }
        let raw = String(text[text.index(after: first)..<last])
        // The smartbox response contains escaped Unicode inside a JS string.
        let decoded = (try? JSONDecoder().decode(String.self, from: Data(("\"" + raw + "\"").utf8))) ?? raw
        var seen = Set<String>()
        return decoded.components(separatedBy: "^").compactMap { row in
            let f = row.components(separatedBy: "~")
            guard f.count >= 5, ["sh", "sz", "bj"].contains(f[0]), f[1].count == 6 else { return nil }
            let symbol = f[0] + f[1]
            guard seen.insert(symbol).inserted else { return nil }
            return SearchResult(symbol: symbol, code: f[1], name: f[2], kind: f[4])
        }
    }

    public static func minutes(_ data: Data, symbol: String) throws -> MinuteSeries {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let all = root["data"] as? [String: Any], let stock = all[symbol] as? [String: Any],
              let detail = stock["data"] as? [String: Any], let rows = detail["data"] as? [String],
              let date = detail["date"] as? String, date.count == 8 else { throw MarketError.noData }
        let snapshot = (stock["qt"] as? [String: Any])?[symbol] as? [String]
        let kind = tencentKind(snapshot)
        let isIndex = kind == "ZS" || symbol.hasPrefix("sh000") || symbol.hasPrefix("sz399")
        let volumeScale = tencentVolumeScale(symbol: symbol, kind: kind)
        let points: [MinutePoint] = rows.compactMap { row in
            let f = row.split(separator: " ")
            guard f.count >= 2, f[0].count == 4, let price = Double(f[1]), price.isFinite, price > 0 else { return nil }
            let volume = f.count > 2 ? Double(f[2]) : nil
            let amount = f.count > 3 ? Double(f[3]) : nil
            // An index is not itself traded: aggregate turnover / shares is not
            // its index-level average and would flatten the price chart.
            let average: Double? = isIndex ? nil : volume.flatMap { v in
                amount.flatMap { a in
                    guard v.isFinite, v > 0, a.isFinite, a > 0 else { return nil }
                    let value = a / (v * volumeScale)
                    return value.isFinite && value > 0 ? value : nil
                }
            }
            return MinutePoint(time: String(f[0]), price: price, average: average)
        }
        guard !points.isEmpty else { throw MarketError.noData }
        return MinuteSeries(date: date, points: points)
    }

    public static func breadth(_ data: Data, delayed: Bool = false) throws -> MarketBreadth {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any], let rows = payload["diff"] as? [[String: Any]], rows.count == 2,
              rows.allSatisfy({ $0["f104"] is NSNumber && $0["f105"] is NSNumber && $0["f106"] is NSNumber && $0["f6"] is NSNumber }) else { throw MarketError.invalidResponse }
        func sum(_ key: String) -> Int { rows.reduce(0) { $0 + (($1[key] as? NSNumber)?.intValue ?? 0) } }
        return MarketBreadth(up: sum("f104"), flat: sum("f106"), down: sum("f105"),
                             amount: rows.reduce(0) { $0 + (($1["f6"] as? NSNumber)?.doubleValue ?? 0) }, fetchedAt: Date(), delayed: delayed)
    }
}

public struct MarketService {
    private let log: RequestLog
    private let session: URLSession
    public init(log: RequestLog = .shared, session: URLSession = .shared) { self.log = log; self.session = session }
    func tracked<T>(_ endpoint: String, complete: (T) -> Bool = { _ in true }, _ body: () async throws -> T) async throws -> T {
        let start = Date()
        do {
            let result = try await body()
            let valid = complete(result)
            await log.record(.init(scope: "operation", endpoint: endpoint, outcome: valid ? "success" : "failure", milliseconds: Int(Date().timeIntervalSince(start) * 1000), error: valid ? nil : "partial_response"))
            return result
        } catch {
            await log.record(.init(scope: "operation", endpoint: endpoint, outcome: RequestLog.outcome(error), milliseconds: Int(Date().timeIntervalSince(start) * 1000), error: RequestLog.errorCode(error)))
            throw error
        }
    }
    func get(_ url: String, timeout: TimeInterval = 12, retry: Bool = true) async throws -> Data {
        guard let url = URL(string: url) else { throw MarketError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 13_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(url.host?.contains("eastmoney.com") == true ? "https://quote.eastmoney.com/" : "https://gu.qq.com/", forHTTPHeaderField: "Referer")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        var responseData: (Data, URLResponse)?
        for attempt in 0..<(retry ? 2 : 1) {
            let start = Date()
            var status: Int?
            let endpoint = (url.host ?? "unknown") + (url.path.hasPrefix("/q=") ? "/q" : url.path)
            do {
                let response = try await session.data(for: request)
                status = (response.1 as? HTTPURLResponse)?.statusCode
                guard let code = status, (200..<300).contains(code) else { throw MarketError.invalidResponse }
                await log.record(.init(scope: "http", endpoint: endpoint, outcome: "success", milliseconds: Int(Date().timeIntervalSince(start) * 1000), status: status))
                responseData = response; break
            } catch {
                await log.record(.init(scope: "http", endpoint: endpoint, outcome: RequestLog.outcome(error), milliseconds: Int(Date().timeIntervalSince(start) * 1000), status: status, error: RequestLog.errorCode(error)))
                guard retry, attempt == 0, !Task.isCancelled,
                      let networkError = error as? URLError,
                      [.networkConnectionLost, .timedOut, .cannotConnectToHost].contains(networkError.code) else { throw error }
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        guard let (data, response) = responseData else { throw MarketError.noData }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw MarketError.invalidResponse }
        return data
    }
    public func quotes(_ symbols: [String]) async throws -> [Quote] {
        return try await tracked("腾讯 · 报价", complete: { Set($0.map(\.symbol)).isSuperset(of: Set(symbols)) }) {
            guard !symbols.isEmpty else { return [] }
            let allowed = symbols.filter { $0.range(of: #"^(sh|sz|bj)\d{6}$"#, options: .regularExpression) != nil }
            guard !allowed.isEmpty else { throw MarketError.noData }
            var result: [Quote] = []
            for start in stride(from: 0, to: allowed.count, by: 50) {
                let batch = allowed[start..<min(start + 50, allowed.count)].joined(separator: ",")
                let data = try await get("https://qt.gtimg.cn/q=" + batch)
                result += MarketParser.quotes(try MarketParser.decode(data))
            }
            guard !result.isEmpty else { throw MarketError.noData }
            return result
        }
    }
    public func search(_ query: String) async throws -> [SearchResult] {
        return try await tracked("腾讯 · 搜索") {
            var parts = URLComponents(string: "https://smartbox.gtimg.cn/s3/")!
            parts.queryItems = [.init(name: "q", value: query), .init(name: "t", value: "all")]
            return MarketParser.search(try MarketParser.decode(try await get(parts.url!.absoluteString)))
        }
    }
    public func minutes(_ symbol: String) async throws -> MinuteSeries {
        return try await tracked("腾讯 · 分时") {
            try MarketParser.minutes(try await get("https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=" + symbol), symbol: symbol)
        }
    }
    public func breadth() async throws -> MarketBreadth {
        return try await tracked("东财 · 市场统计") {
            let path = "/api/qt/ulist.np/get?fltt=2&secids=1.000001,0.399001&fields=f12,f14,f104,f105,f106,f6"
            var lastError: Error = MarketError.noData
            for host in ["push2.eastmoney.com", "push2delay.eastmoney.com"] {
                do {
                    let data = try await get("https://" + host + path, timeout: 4, retry: false)
                    return try MarketParser.breadth(data, delayed: host.contains("delay"))
                } catch { if Task.isCancelled { throw error }; lastError = error }
            }
            throw lastError
        }
    }
}

public enum MarketFormat {
    public static func percent(_ n: Double?) -> String { n.map { String(format: "%+.2f%%", $0) } ?? "—" }
    public static func compact(_ n: Double?) -> String {
        guard let n = n, n.isFinite else { return "—" }
        if abs(n) >= 1_000_000_000_000 { return String(format: "%.2f万亿", n / 1_000_000_000_000) }
        if abs(n) >= 100_000_000 { return String(format: abs(n) >= 100_000_000_000 ? "%.0f亿" : "%.2f亿", n / 100_000_000) }
        if abs(n) >= 10_000 { return String(format: "%.0f万", n / 10_000) }
        return String(format: "%.0f", n)
    }
}
