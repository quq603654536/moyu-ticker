import SwiftUI

/// Keep the complete dashboard layout and scale it to the independent window.
/// Scaling the actual SwiftUI view preserves all controls and hit testing.
struct ScaledDashboardView: View {
    static let canvasSize = NSSize(width: 1240, height: 800)
    static let initialSize = NSSize(width: 558, height: 360)
    static let minimumSize = NSSize(width: 360, height: 800 * 360 / 1240)

    @ObservedObject var store: MarketStore
    let openWindow: () -> Void
    let close: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let canvas = Self.canvasSize
            let scale = min(geometry.size.width / canvas.width, geometry.size.height / canvas.height)
            DashboardView(store: store, openWindow: openWindow, close: close)
                .frame(width: canvas.width, height: canvas.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }.background(.white)
    }
}
