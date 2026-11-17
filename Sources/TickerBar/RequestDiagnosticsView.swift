import SwiftUI
import MarketCore

struct RequestDiagnosticsView: View {
    let log: RequestLog
    init(log: RequestLog = .shared) { self.log = log }
    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: RequestLogSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("接口日志与统计").font(.system(size: 19, weight: .semibold))
                Spacer()
                IconButton(icon: "xmark", help: "关闭") { dismiss() }
            }
            Text("最近 7 天 · 失败率 = 失败次数 ÷ 已完成次数 · 取消请求不计入\n仅统计安装本版本后的请求；短期样本不代表长期稳定性。")
                .font(.system(size: 11)).foregroundColor(Palette.muted).lineSpacing(4)
            if let snapshot = snapshot {
                if let since = snapshot.since {
                    Text("最早记录：\(since.formatted(date: .numeric, time: .shortened))").font(.system(size: 10)).foregroundColor(Palette.muted)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        rows("最终数据更新", scope: "operation", snapshot: snapshot)
                        rows("网络请求（含重试、备用接口）", scope: "http", snapshot: snapshot)
                    }
                }
                if let error = snapshot.storageError {
                    Text("日志写入失败：\(error)").font(.system(size: 10)).foregroundColor(.orange)
                }
            } else { ProgressView().frame(maxWidth: .infinity) }
            Text("最终数据更新包括解析与空数据检查；网络请求按 HTTP 状态判断。日志只保存在本机，记录时间、接口、耗时、状态码和错误码，不记录自选代码、搜索词或响应内容。")
                .font(.system(size: 10)).foregroundColor(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { NSWorkspace.shared.open(log.directory) } label: {
                    Text("打开日志文件夹").padding(.horizontal, 10).padding(.vertical, 7).background(Palette.canvas).cornerRadius(5)
                }.buttonStyle(.plain)
                Spacer()
                Button { Task { snapshot = await log.snapshot() } } label: {
                    Text("刷新统计").padding(.horizontal, 10).padding(.vertical, 7).background(Palette.canvas).cornerRadius(5)
                }.buttonStyle(.plain)
            }.font(.system(size: 11))
        }.padding(22).frame(width: 570, height: 480).background(.white).foregroundColor(Palette.ink)
        .task {
            while !Task.isCancelled {
                snapshot = await log.snapshot()
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            }
        }
    }
    private func rows(_ title: String, scope: String, snapshot: RequestLogSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.purple)
            let rows = snapshot.statistics.filter { $0.scope == scope }
            if rows.isEmpty { Text("暂无记录").font(.system(size: 11)).foregroundColor(Palette.muted) }
            if !rows.isEmpty {
                HStack { Spacer(); Text("失败 / 完成").frame(width: 72, alignment: .trailing); Text("失败率").frame(width: 56, alignment: .trailing) }
                    .font(.system(size: 10)).foregroundColor(Palette.muted)
            }
            ForEach(rows) { row in
                HStack(alignment: .top) {
                    Text(row.endpoint).font(.system(size: 10)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.failures) / \(row.total)").frame(width: 72, alignment: .trailing)
                    Text(String(format: "%.1f%%", row.failureRate * 100)).frame(width: 56, alignment: .trailing)
                }.font(.system(size: 11, design: .monospaced))
            }
        }
    }
}
