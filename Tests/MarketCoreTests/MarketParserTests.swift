import Foundation
import MarketCore

private struct CheckFailure: Error, CustomStringConvertible { let description: String }
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure(description: message) }
}

private func validate(fixtures: URL) throws {
    func data(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }
    let quotes = MarketParser.quotes(try MarketParser.decode(data("quotes.gbk")))
    try require(quotes.count == 3, "Decode all GB18030 quotes")
    let bank = try quotes.first(where: { $0.symbol == "sh601288" }).unwrap("Agricultural Bank quote missing")
    try require(bank.name == "农业银行", "Chinese name decoding")
    try require(bank.price == 7.54 && bank.previousClose == 7.59, "Price/previous close mapping")
    try require(bank.percent == -0.66 && bank.change == -0.05, "Daily change mapping")
    try require(bank.ytd == 1.62, "YTD follows GP-A marker, not field 61")
    try require(bank.kind == "GP-A", "Security type mapping")
    try require(bank.volume == 173_789_500, "Convert hands to shares")
    try require(bank.amount == 1_314_300_000, "Convert 10,000 yuan to yuan")
    try require(bank.marketCap == 2_638_872_000_000, "Convert market cap from 100M yuan")
    try require(bank.quoteDate != nil, "Shanghai timestamp parsing")
    try require(quotes[0].ytd == -9.94, "Index YTD mapping")
    let stocks = MarketParser.quotes(try MarketParser.decode(data("stocks.gbk")))
    let etf = try stocks.first(where: { $0.symbol == "sh588010" }).unwrap("ETF quote missing")
    try require(etf.isFund && etf.priceText == "0.747", "ETF keeps three decimals")
    try require(etf.ytd == -13.54, "ETF YTD mapping")
    try require(bank.priceText == "7.54", "Equity keeps two decimals")
    try require(MarketParser.quotes("v_pv_none_match=\"1\";").isEmpty, "Reject invalid quote payload")
    try require(MarketParser.quotes("bad input").isEmpty, "Reject malformed response")
    let search = MarketParser.search(try MarketParser.decode(data("search.txt")))
    try require(search.first?.name == "农业银行", "Decode search Unicode escapes")
    try require(search.first?.symbol == "sh601288", "Search symbol mapping")
    try require(!search.contains(where: { $0.symbol.hasPrefix("hk") }), "Filter unsupported market")
    try require(MarketParser.search("v_hint=\"N\"").isEmpty, "No-result search")
    let minute = try MarketParser.minutes(data("minute.json"), symbol: "sh601288")
    try require(minute.date == "20261117", "Minute-series date")
    try require(minute.points.first?.price == 7.59, "Minute-series price mapping")
    try require(minute.points.first?.minute == 0, "09:30 maps to session start")
    try require(abs((minute.points.first?.average ?? 0) - 7.589) < 0.01, "Volume weighted average uses shares")
    try require(minute.matches(bank), "Allow same-day trend")
    try require(!minute.matches(nil), "Never show unverified/stale trend")
    let lunchJSON = Data(#"{"data":{"sh601288":{"data":{"date":"20261116","data":["1130 7.5 0 0","1300 7.5 0 0","1500 7.6 0 0"]}}}}"#.utf8)
    let lunch = try MarketParser.minutes(lunchJSON, symbol: "sh601288")
    try require(lunch.points.map(\.minute) == [120, 120, 240], "Exclude lunch break from chart x-axis")
    try require(!lunch.matches(bank), "Hide prior-day trend against current quote")
    try require(lunch.points[0].average == nil, "Avoid division by zero")
    let indexJSON = Data(#"{"data":{"sh000001":{"data":{"date":"20261117","data":["0930 3580.00 100000 10000000.00"]}}}}"#.utf8)
    let indexSeries = try MarketParser.minutes(indexJSON, symbol: "sh000001")
    try require(indexSeries.points[0].average == nil, "Index turnover must not create a fake VWAP or flatten chart")
    // Provider recordings from the reported HaiGuang regression (2026-11-19).
    func recordedQuote(_ file: String, _ symbol: String) throws -> Quote {
        let root = try JSONSerialization.jsonObject(with: data(file)) as! [String: Any]
        let stock = (root["data"] as! [String: Any])[symbol] as! [String: Any]
        let fields = (stock["qt"] as! [String: Any])[symbol] as! [String]
        return try MarketParser.quotes("v_\(symbol)=\"" + fields.joined(separator: "~") + "\";").first.unwrap("Recorded quote missing")
    }
    let starQuote = try recordedQuote("minute-star.json", "sh688041")
    let starMinute = try MarketParser.minutes(data("minute-star.json"), symbol: "sh688041")
    try require(starQuote.kind == "GP-A-KCB" && starQuote.ytd == -24.80, "Recognize STAR security marker and performance fields")
    try require(starQuote.volume == 40_904_667, "STAR quote volume is already shares, not lots")
    try require(starMinute.points.first?.average == 185, "STAR opening VWAP is 185 yuan, never 1.85")
    try require(abs((starMinute.points.last?.average ?? 0) - 6_735_871_987.0 / 40_904_667) < 0.000001, "STAR cumulative amount / shares gives real VWAP")
    try require(starMinute.points.allSatisfy { ($0.average ?? 0) >= starQuote.low && ($0.average ?? 0) <= starQuote.high }, "Recorded STAR averages stay inside the actual trading range")
    let starCandle = try MarketParser.candles(data("kline-star.json"), symbol: "sh688041", period: .day, adjustment: .forward)
    try require(starCandle.bars.last?.volume == 40_942_317, "STAR K-line volume is already shares")
    let cdrCandle = try MarketParser.candles(data("kline-star-cdr.json"), symbol: "sh689009", period: .day, adjustment: .forward)
    try require(cdrCandle.bars.last?.volume == 6_096_941, "STAR CDR volume follows share units too")
    let chinextQuote = try recordedQuote("minute-chinext.json", "sz300750")
    let chinextMinute = try MarketParser.minutes(data("minute-chinext.json"), symbol: "sz300750")
    try require(chinextQuote.kind == "GP-A-CYB" && chinextQuote.ytd == -34.46, "Recognize ChiNext subtype without treating it as STAR")
    try require(chinextQuote.volume == 23_904_600, "ChiNext remains lots converted to shares")
    try require(abs((chinextMinute.points.first?.average ?? 0) - 239.93) < 0.001, "ChiNext VWAP keeps the lot conversion")
    let etfMinuteJSON = Data(#"{"data":{"sh588010":{"data":{"date":"20261119","data":["0930 0.741 79 5854"]}}}}"#.utf8)
    let etfMinute = try MarketParser.minutes(etfMinuteJSON, symbol: "sh588010")
    try require(abs((etfMinute.points[0].average ?? 0) - 5854.0 / 7900) < 0.000001, "ETF VWAP keeps the lot conversion")
    let noMetadataJSON = Data(#"{"data":{"sh688041":{"data":{"date":"20261119","data":["0930 185 258304 47786240","0931 185 0 0","0932 185 nan 100","0933 185 100 inf"]}}}}"#.utf8)
    let noMetadata = try MarketParser.minutes(noMetadataJSON, symbol: "sh688041")
    try require(noMetadata.points[0].average == 185, "STAR symbol determines units even if quote metadata is absent")
    try require(noMetadata.points.dropFirst().allSatisfy { $0.average == nil }, "Invalid totals cannot create a zero or nonfinite average line")
    let yellowJSON = Data(#"{"rc":0,"data":{"code":"000001","market":1,"prePrice":3500,"trends":["2026-11-18 09:30,3500,3501,3502,3499,100,10000,3490.500","2026-11-18 09:31,3520,3521,3522,3510,100,10000,3478.000"]}}"#.utf8)
    let yellow = try MarketParser.leadingIndex(yellowJSON)
    try require(yellow.quote.symbol == LeadingIndex.symbol && yellow.quote.price == 3478, "Yellow curve uses f58, never the blue close or turnover/volume")
    try require(abs(yellow.quote.percent - (3478.0 / 3500 - 1) * 100) < 0.000001, "Yellow change uses provider's chart baseline")
    try require(yellow.quote.change == -22 && yellow.series.points[0].price == 3490.5, "Preserve yellow point levels and change")
    try require(yellow.quote.timestamp == "20261118093100" && yellow.series.matches(yellow.quote), "Yellow quote and minutes share the source trading date")
    try require(yellow.series.points.allSatisfy { $0.average == nil }, "Do not mislabel the leading curve as stock VWAP")
    let badYellow = Data(#"{"rc":0,"data":{"code":"000001","market":1,"prePrice":3500,"trends":["2026-11-18 09:30,3500,3501,3502,3499,100,10000,0","2026-11-18 09:31,3520,3521,3522,3510,100,10000,--"]}}"#.utf8)
    do { _ = try MarketParser.leadingIndex(badYellow); throw CheckFailure(description: "Must reject unavailable yellow data") }
    catch is MarketError {}
    let cachedYellow = try JSONDecoder().decode(LeadingIndexSnapshot.self, from: JSONEncoder().encode(yellow))
    try require(cachedYellow.quote == yellow.quote && cachedYellow.series == yellow.series, "Yellow quote and series survive cache round trip")
    let breadth = try MarketParser.breadth(data("breadth.json"))
    try require(breadth.up == 1769 && breadth.down == 3317 && breadth.flat == 208, "Combine Shanghai/Shenzhen breadth")
    try require(breadth.amount > 700_000_000_000, "Breadth amount remains in yuan")
    try require(MarketFormat.percent(1.25) == "+1.25%", "Positive percentage sign")
    try require(MarketFormat.percent(nil) == "—", "Missing performance stays missing")
    try require(MarketFormat.compact(1_500_000_000_000) == "1.50万亿", "Large-unit formatting")
    let daily = try MarketParser.candles(data("kline-day.json"), symbol: "sh601288", period: .day, adjustment: .forward)
    try require(daily.bars.count == 321, "Parse complete daily history including current bar")
    try require(daily.bars[0].open == 5.801 && daily.bars[0].close == 5.721, "OHLC field order: open, close, high, low")
    try require(daily.bars[0].high == 5.811 && daily.bars[0].low == 5.701, "Daily high/low mapping")
    try require(daily.bars[0].volume == 560_928_300, "K-line hands converted to shares")
    try require(daily.adjustment == .forward, "Preserve forward-adjustment provenance")
    let weekly = try MarketParser.candles(data("kline-week.json"), symbol: "sh601288", period: .week, adjustment: .forward)
    try require(weekly.bars.count == 320 && weekly.period == .week, "Weekly history decoding")
    let monthly = try MarketParser.candles(data("kline-month.json"), symbol: "sh601288", period: .month, adjustment: .forward)
    try require(monthly.bars.count == 197, "Preserve complete monthly history")
    try require(monthly.bars[0].open == -0.298 && monthly.bars[0].low == -0.358, "Negative historical forward-adjusted prices are valid")
    let unadjusted = try MarketParser.candles(data("kline-unadjusted.json"), symbol: "sh601288", period: .day, adjustment: .none)
    try require(unadjusted.adjustment == .none && unadjusted.bars.last?.close == 7.60, "Unadjusted history is independent")
    let etfCandles = try MarketParser.candles(data("kline-etf.json"), symbol: "sh588010", period: .day, adjustment: .forward)
    try require(etfCandles.bars.last?.close == 0.758 && etfCandles.adjustment == .none, "ETF fallback preserves actual unadjusted price provenance")
    let indexCandles = try MarketParser.candles(data("kline-index.json"), symbol: "sh000852", period: .day, adjustment: .none)
    try require(indexCandles.bars.count == 321 && indexCandles.bars.last?.high == 6225.56, "CSI 1000 candle history")
    let shortJSON = Data(#"{"code":0,"data":{"sh601288":{"day":[["2026-11-03",3,6,7,2,12],["2026-11-01",1,2,3,0,10],["2026-11-02",2,3,4,1,11],["2026-11-02",2,4,5,1,11],["bad",0,0,0,0,0],["2026-11-04",9,9,2,8,10]]}}}"#.utf8)
    let short = try MarketParser.candles(shortJSON, symbol: "sh601288", period: .day, adjustment: .forward)
    try require(short.bars.map(\.date) == ["2026-11-01", "2026-11-02", "2026-11-03"], "Sort dates, deduplicate and reject malformed OHLC")
    try require(short.adjustment == .none, "Report actual unadjusted fallback instead of mislabelling")
    let ma = short.movingAverage(length: 2)
    try require(ma[0] == nil && ma[1] == 3 && ma[2] == 5, "Rolling MA warm-up and full-history calculation")
    try require(short.movingAverage(length: 5).allSatisfy { $0 == nil }, "No invented MA before enough history")
    do {
        _ = try MarketParser.candles(Data(#"{"code":0,"data":{"sh601288":{"day":[]}}}"#.utf8), symbol: "sh601288", period: .day, adjustment: .none)
        throw CheckFailure(description: "Empty history should fail")
    } catch is MarketError { }
    print("PASS: market-data parsing, date, units and formatting checks")
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw CheckFailure(description: message) }
        return value
    }
}

#if SWIFT_PACKAGE
import XCTest
final class MarketParserTests: XCTestCase {
    func testRealMarketFixtures() throws { try validate(fixtures: Bundle.module.resourceURL!.appendingPathComponent("Fixtures")) }
}
#else
@main struct TestRunner {
    static func main() async throws {
        try validate(fixtures: URL(fileURLWithPath: CommandLine.arguments[1]))
        if CommandLine.arguments.contains("--live") {
            let service = MarketService()
            let quotes = try await service.quotes(["sh000001", "sz399001", "sz399006", "sh000688", "sh000300", "sh000852", "sh601288", "sh588010"])
            try require(quotes.count == 8, "Live quotes return all eight symbols")
            let bank = try quotes.first(where: { $0.symbol == "sh601288" }).unwrap("Live bank quote")
            let trend = try await service.minutes(bank.symbol)
            try require(trend.matches(bank), "Live trend matches quote date")
            let results = try await service.search("农业")
            try require(results.contains(where: { $0.symbol == "sh601288" }), "Live search resolves bank")
            let breadth = try await service.breadth()
            try require(breadth.up + breadth.down + breadth.flat > 4000, "Live market breadth")
            print("PASS: live quotes, intraday trend, Chinese search, market breadth")
            print("Live quote: \(bank.name) \(bank.priceText) \(MarketFormat.percent(bank.percent)) at \(bank.timestamp)")
        }
    }
}
#endif
