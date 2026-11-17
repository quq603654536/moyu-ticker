import Foundation

/// Display rotation uses cached quotes and never schedules network refreshes.
@MainActor final class MenuBarRotation {
    static let interval: TimeInterval = 3
    private var symbols = [String]()
    private var index = 0
    private var timer: Timer?
    var onChange: (() -> Void)?
    var symbol: String { symbols.isEmpty ? MarketStore.indices[0] : symbols[index] }

    func configure(_ selection: [String]) {
        timer?.invalidate()
        symbols = selection
        index = 0
        onChange?()
        guard symbols.count > 1 else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            guard let rotation = self else { return }
            Task { @MainActor in
                guard rotation.symbols.count > 1 else { return }
                rotation.index = (rotation.index + 1) % rotation.symbols.count
                rotation.onChange?()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }
}
