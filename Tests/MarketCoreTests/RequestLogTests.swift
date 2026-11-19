import Foundation
import MarketCore

private enum Failure: Error { case check(String) }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw Failure.check(message) }
}
private final class Stub: URLProtocol {
    enum Reply { case data(Int, Data), error(URLError) }
    static var replies: [Reply] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard !Self.replies.isEmpty else { client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return }
        switch Self.replies.removeFirst() {
        case let .error(error): client?.urlProtocol(self, didFailWithError: error)
        case let .data(code, data):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
@main struct RequestLogTests {
    static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ticker-log-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = RequestLog(directory: directory)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [Stub.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        let service = MarketService(log: log, session: session)
        let quoteData = try Data(contentsOf: fixtures.appendingPathComponent("quotes.gbk"))
        let symbols = MarketParser.quotes(try MarketParser.decode(quoteData)).map(\.symbol)
        Stub.replies = [.error(URLError(.networkConnectionLost)), .data(200, quoteData)]
        _ = try await service.quotes(symbols)
        var snapshot = await log.snapshot()
        func row(_ snapshot: RequestLogSnapshot, scope: String, name: String) -> RequestStatistic? {
            snapshot.statistics.first { $0.scope == scope && $0.endpoint.contains(name) }
        }
        try check(row(snapshot, scope: "http", name: "qt.gtimg")?.failures == 1, "Retry must preserve the failed HTTP attempt")
        try check(row(snapshot, scope: "http", name: "qt.gtimg")?.total == 2, "Retry creates two physical attempts")
        try check(row(snapshot, scope: "operation", name: "报价")?.failures == 0, "Recovered retry is a successful final update")
        Stub.replies = [.data(200, Data("invalid".utf8)), .data(200, try Data(contentsOf: fixtures.appendingPathComponent("breadth.json")))]
        let breadth = try await service.breadth()
        try check(breadth.delayed == true, "Fallback provenance remains intact")
        snapshot = await log.snapshot()
        try check(row(snapshot, scope: "operation", name: "东财")?.failures == 0, "Fallback parsing recovery is a successful final update")
        Stub.replies = [.data(503, Data()), .data(503, Data())]
        do { _ = try await service.breadth(); throw Failure.check("Expected HTTP failure") }
        catch is Failure { throw Failure.check("Expected HTTP failure") } catch {}
        snapshot = await log.snapshot()
        try check(row(snapshot, scope: "operation", name: "东财")?.failureRate == 0.5, "Final rate is one failure over two logical updates")
        Stub.replies = [.data(200, Data("invalid".utf8))]
        do { _ = try await service.quotes(symbols); throw Failure.check("Expected payload failure") }
        catch is Failure { throw Failure.check("Expected payload failure") } catch {}
        Stub.replies = [.data(200, quoteData)]
        let partial = try await service.quotes(symbols + ["sh999999"])
        try check(partial.count == symbols.count, "Keep useful partial quotes")
        Stub.replies = [.error(URLError(.cancelled))]
        do { _ = try await service.quotes(symbols) } catch {}
        snapshot = await log.snapshot()
        try check(row(snapshot, scope: "operation", name: "报价")?.total == 3, "Cancellation excluded from denominator")
        try check(row(snapshot, scope: "operation", name: "报价")?.failures == 2, "Empty and partial payloads count as final failures")
        let leadingJSON = Data(#"{"rc":0,"data":{"code":"000001","market":1,"preClose":3500,"trends":["2026-11-18 09:30,3500,3501,3502,3499,100,10000,3490.5"]}}"#.utf8)
        Stub.replies = [.data(200, Data("invalid".utf8)), .data(200, leadingJSON)]
        let leading = try await service.leadingIndex()
        try check(leading.delayed && leading.quote.price == 3490.5, "Leading curve recovers through delayed host with provenance")
        Stub.replies = [.error(URLError(.cancelled))]
        do { _ = try await service.leadingIndex(); throw Failure.check("Expected leading cancellation") }
        catch let error as URLError { try check(error.code == .cancelled, "Leading cancellation does not try fallback") }
        let reloaded = await RequestLog(directory: directory).snapshot()
        try check(row(reloaded, scope: "operation", name: "报价")?.total == 3, "Statistics survive restart")
        let text = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }.map { try String(contentsOf: $0) }.joined()
        try check(!text.contains("sh601288") && !text.contains("secids") && !text.contains("q="), "Logs omit symbols and URL query parameters")
        let expired = await RequestLog(directory: directory).snapshot(now: Date().addingTimeInterval(9 * 86400))
        try check(expired.statistics.isEmpty, "Seven-day retention excludes old records")
        print("Request diagnostics passed: retries, fallback, HTTP/parse/partial failures, cancellation, persistence, retention and privacy")
    }
}
