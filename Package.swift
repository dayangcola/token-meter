// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIQuotaBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AIQuotaBar", targets: ["AIQuotaBar"])],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(name: "AIQuotaBar", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
    ]
)
