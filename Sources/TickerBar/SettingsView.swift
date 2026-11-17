import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: MarketStore
    @Environment(\.dismiss) private var dismiss
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var showDiagnostics = false
    @State private var showMenuSelection = false
    @State private var needsApproval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("偏好设置").font(.system(size: 22, weight: .semibold))
                Spacer()
                IconButton(icon: "xmark", help: "关闭设置") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("菜单栏").font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.purple)
                HStack {
                    Text("显示行情").font(.system(size: 12))
                    Spacer()
                    Button { showMenuSelection.toggle() } label: {
                        HStack(spacing: 6) {
                            Text("已选 \(store.menuSymbols.count) 项")
                            Image(systemName: "chevron.down").font(.system(size: 9))
                        }.foregroundColor(Palette.purple)
                    }.buttonStyle(.plain)
                        .popover(isPresented: $showMenuSelection) { MenuSelectionView(store: store) }
                }
                Toggle("同时显示价格", isOn: $store.menuShowPrice).toggleStyle(.switch).controlSize(.small)
                Toggle("行情窗口置顶", isOn: $store.pinned).toggleStyle(.switch).controlSize(.small)
                Text("多选后每 3 秒轮播 · 左键打开窗口 · 右键菜单").font(.system(size: 10)).foregroundColor(Palette.muted)
            }.font(.system(size: 12)).padding(18).background(Palette.canvas).cornerRadius(10)
            VStack(alignment: .leading, spacing: 16) {
                Text("更新与启动").font(.system(size: 12, weight: .semibold)).foregroundColor(Palette.purple)
                HStack {
                    Text("行情刷新间隔")
                    Spacer()
                    Picker("刷新间隔", selection: $store.refreshInterval) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 秒").tag($0) }
                    }.labelsHidden().frame(width: 130)
                }
                Toggle("暂停自动刷新", isOn: $store.paused).toggleStyle(.switch).controlSize(.small)
                Toggle("登录 Mac 时启动", isOn: Binding(get: { loginEnabled }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        let status = SMAppService.mainApp.status
                        loginEnabled = status == .enabled
                        needsApproval = status == .requiresApproval
                        message = needsApproval ? "请在系统设置的「登录项」中允许盯盘启动" : nil
                    } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = "设置失败：" + error.localizedDescription }
                })).toggleStyle(.switch).controlSize(.small)
                if let message = message { Text(message).font(.system(size: 10)).foregroundColor(.orange) }
                if needsApproval { Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() } }
            }.font(.system(size: 12)).padding(18).background(Palette.canvas).cornerRadius(10)
            VStack(alignment: .leading, spacing: 7) {
                Button("接口日志与失败率…") { showDiagnostics = true }
                    .font(.system(size: 12)).foregroundColor(Palette.purple)
                Text("盯盘 TickerBar 1.0").font(.system(size: 12, weight: .medium))
                Text("行情：腾讯财经 · 市场广度：东方财富\n分时约每分钟更新，行情以接口返回时间为准。").font(.system(size: 10)).foregroundColor(Palette.muted).lineSpacing(4)
                HStack(spacing: 16) {
                    Link("腾讯财经", destination: URL(string: "https://gu.qq.com/")!)
                    Link("东方财富", destination: URL(string: "https://quote.eastmoney.com/")!)
                }.font(.system(size: 10)).foregroundColor(Palette.purple)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("完成").foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 7).background(Palette.purple).cornerRadius(6) }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 460).background(.white).foregroundColor(Palette.ink)
        .sheet(isPresented: $showDiagnostics) { RequestDiagnosticsView() }
    }
}
