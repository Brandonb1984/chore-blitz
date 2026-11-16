// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChoreKit",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [.library(name: "ChoreKit", targets: ["ChoreKit"])],
    targets: [
        .target(name: "ChoreKit"),
        .testTarget(name: "ChoreKitTests", dependencies: ["ChoreKit"]),
    ]
)
