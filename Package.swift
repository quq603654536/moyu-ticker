// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "TickerBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TickerBar", targets: ["TickerBar"])],
    targets: [
        .target(name: "MarketCore"),
        .executableTarget(name: "TickerBar", dependencies: ["MarketCore"]),
        .testTarget(name: "MarketCoreTests", dependencies: ["MarketCore"], resources: [.copy("Fixtures")])
    ]
)
