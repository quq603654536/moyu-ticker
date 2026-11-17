import SwiftUI

struct MenuSelectionView: View {
    @ObservedObject var store: MarketStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("菜单栏行情").font(.system(size: 15, weight: .semibold))
            Text("可选择多项，每 3 秒依次展示；至少保留一项。")
                .font(.system(size: 10)).foregroundColor(Palette.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("指数").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.purple)
                    ForEach(MarketStore.indices, id: \.self) { row($0) }
                    Divider().padding(.vertical, 2)
                    Text("自选").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.purple)
                    ForEach(store.items.filter { !MarketStore.indices.contains($0.symbol) }) { row($0.symbol) }
                    let extra = store.menuSymbols.filter { !MarketStore.indices.contains($0) && !store.items.map(\.symbol).contains($0) }
                    if !extra.isEmpty {
                        Divider().padding(.vertical, 2)
                        Text("其他已选").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.purple)
                        ForEach(extra, id: \.self) { row($0) }
                    }
                }.padding(.trailing, 6)
            }
            Text("已选 \(store.menuSymbols.count) 项 · 按勾选顺序轮播")
                .font(.system(size: 10)).foregroundColor(Palette.muted)
        }.padding(18).frame(width: 300, height: 380).foregroundColor(Palette.ink).background(.white)
    }
    private func row(_ symbol: String) -> some View {
        Toggle(store.menuName(symbol), isOn: Binding(
            get: { store.menuSymbols.contains(symbol) },
            set: { store.setMenuSymbol(symbol, enabled: $0) }
        )).toggleStyle(.checkbox).font(.system(size: 12))
            .disabled(store.menuSymbols == [symbol])
    }
}
