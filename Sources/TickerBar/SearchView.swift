import SwiftUI
import MarketCore

struct SearchView: View {
    @ObservedObject var store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var loading = false
    @State private var error: String?
    @State private var targetGroup: StockGroup = .value
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("添加自选").font(.system(size: 22, weight: .semibold))
                    Text("搜索 A 股、ETF 和指数，支持名称、代码或拼音").font(.system(size: 11)).foregroundColor(Palette.muted)
                }
                Spacer()
                IconButton(icon: "xmark", help: "关闭搜索") { dismiss() }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(Palette.purple)
                TextField("例如：农业银行 / 601288 / nyyh", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
                if loading { ProgressView().controlSize(.small) }
            }.padding(13).background(Palette.canvas).cornerRadius(9)
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Palette.purple.opacity(0.2)) }
            HStack {
                Text("添加到").font(.system(size: 11)).foregroundColor(Palette.muted)
                Picker("分组", selection: $targetGroup) {
                    ForEach(StockGroup.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                Spacer()
            }
            ScrollView {
                VStack(spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        emptyState("magnifyingglass", "输入名称或代码开始搜索")
                    } else if let error = error {
                        emptyState("wifi.exclamationmark", error)
                    } else if results.isEmpty && !loading {
                        emptyState("tray", "未找到结果，试试六位股票代码")
                    } else {
                        ForEach(results) { result in
                            let exists = store.items.contains { $0.symbol == result.symbol }
                            HStack(spacing: 12) {
                                Text(String(result.symbol.prefix(2)).uppercased()).font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Palette.purple).frame(width: 29, height: 29)
                                    .background(Palette.purple.opacity(0.07)).cornerRadius(6)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.name).font(.system(size: 13, weight: .medium))
                                    Text(result.code + "  ·  " + result.kind).font(.system(size: 10)).foregroundColor(Palette.muted)
                                }
                                Spacer()
                                Button(exists ? "已添加" : "＋ 添加") { store.add(result, group: targetGroup) }
                                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                                    .foregroundColor(exists ? Palette.muted : Palette.purple)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(exists ? Palette.canvas : Palette.purple.opacity(0.08)).cornerRadius(6)
                                    .disabled(exists)
                            }.padding(.vertical, 12)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }.frame(height: 290)
            HStack {
                Text("自选数据仅保存在这台 Mac 上").font(.system(size: 10)).foregroundColor(Palette.muted)
                Spacer()
                Button { dismiss() } label: { Text("完成").foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 7).background(Palette.purple).cornerRadius(6) }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 510).background(.white).foregroundColor(Palette.ink)
            .onAppear { targetGroup = store.group; focused = true }
            .task(id: query) {
                let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
                results = []; error = nil
                guard !value.isEmpty else { loading = false; return }
                loading = true
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    let found = try await store.search(value)
                    try Task.checkCancellation()
                    results = found
                    loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    self.error = "搜索暂不可用，请检查网络后重试"
                    loading = false
                }
            }
    }
    private func emptyState(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundColor(Palette.purple.opacity(0.5))
            Text(label).font(.system(size: 12)).foregroundColor(Palette.muted)
        }.frame(maxWidth: .infinity).padding(.top, 85)
    }
}
