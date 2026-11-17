import Foundation

public struct RequestRecord: Codable {
    public let date: Date
    public let scope: String
    public let endpoint: String
    public let outcome: String
    public let milliseconds: Int
    public let status: Int?
    public let error: String?

    public init(date: Date = Date(), scope: String, endpoint: String, outcome: String, milliseconds: Int, status: Int? = nil, error: String? = nil) {
        self.date = date; self.scope = scope; self.endpoint = endpoint; self.outcome = outcome
        self.milliseconds = milliseconds; self.status = status; self.error = error
    }
}

public struct RequestStatistic: Identifiable {
    public var id: String { scope + endpoint }
    public let scope: String
    public let endpoint: String
    public let successes: Int
    public let failures: Int
    public var total: Int { successes + failures }
    public var failureRate: Double { total == 0 ? 0 : Double(failures) / Double(total) }
}

public struct RequestLogSnapshot {
    public let since: Date?
    public let statistics: [RequestStatistic]
    public let storageError: String?
}

/// Local diagnostics only: never records query parameters, security symbols or response bodies.
public actor RequestLog {
    public static let shared = RequestLog()
    public nonisolated let directory: URL
    private var records: [RequestRecord] = []
    private var loaded = false
    private var preparedDay: URL?
    private var storageError: String?
    private let retention: TimeInterval = 7 * 24 * 60 * 60

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("盯盘/Logs", isDirectory: true)
    }
    private func file(_ day: Date) -> URL {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return directory.appendingPathComponent(formatter.string(from: day) + ".jsonl")
    }
    private func prepare(now: Date) {
        let day = file(now)
        guard !loaded || preparedDay != day else { return }
        let firstRead = !loaded
        loaded = true
        preparedDay = day
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "jsonl" {
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
                guard let date = formatter.date(from: url.deletingPathExtension().lastPathComponent) else { continue }
                if now.timeIntervalSince(date) > retention + 86400 { try FileManager.default.removeItem(at: url); continue }
                if firstRead {
                    let data = try Data(contentsOf: url)
                    records += data.split(separator: 10).compactMap { try? JSONDecoder().decode(RequestRecord.self, from: Data($0)) }
                }
            }
        } catch { storageError = error.localizedDescription }
        records.removeAll { now.timeIntervalSince($0.date) > retention }
    }
    public func record(_ record: RequestRecord) {
        prepare(now: record.date)
        records.removeAll { record.date.timeIntervalSince($0.date) > retention }
        records.append(record)
        do {
            var data = try JSONEncoder().encode(record); data.append(10)
            let url = file(record.date)
            if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
            storageError = nil
        } catch { storageError = error.localizedDescription }
    }
    public func snapshot(now: Date = Date()) -> RequestLogSnapshot {
        prepare(now: now)
        records.removeAll { now.timeIntervalSince($0.date) > retention }
        let completed = records.filter { $0.outcome != "cancelled" }
        let groups = Dictionary(grouping: completed) { $0.scope + "|" + $0.endpoint }
        let statistics = groups.values.map { rows -> RequestStatistic in
            RequestStatistic(scope: rows[0].scope, endpoint: rows[0].endpoint,
                             successes: rows.filter { $0.outcome == "success" }.count,
                             failures: rows.filter { $0.outcome == "failure" }.count)
        }.sorted { ($0.scope, $0.endpoint) < ($1.scope, $1.endpoint) }
        return RequestLogSnapshot(since: completed.map(\.date).min(), statistics: statistics, storageError: storageError)
    }
    public static func errorCode(_ error: Error) -> String {
        let error = error as NSError
        // Domain and numeric code are sufficient; localized messages can contain full URLs.
        return "\(error.domain):\(error.code)"
    }
    public static func outcome(_ error: Error) -> String {
        (error is CancellationError || (error as? URLError)?.code == .cancelled) ? "cancelled" : "failure"
    }
}
