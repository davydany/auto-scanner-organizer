// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanCore", targets: ["ScanCore"]),
    ],
    targets: [
        .target(name: "ScanCore"),
        .testTarget(name: "ScanCoreTests", dependencies: ["ScanCore"]),
    ]
)
