// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ScanCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScanCore", targets: ["ScanCore"]),
        .library(name: "ScanAdapters", targets: ["ScanAdapters"]),
        .executable(name: "scan-organizer", targets: ["ScanOrganizerCLI"]),
    ],
    targets: [
        .target(name: "ScanCore"),
        .target(name: "ScanAdapters", dependencies: ["ScanCore"]),
        .executableTarget(name: "ScanOrganizerCLI", dependencies: ["ScanCore", "ScanAdapters"]),
        .testTarget(name: "ScanCoreTests", dependencies: ["ScanCore"]),
        .testTarget(name: "ScanAdaptersTests", dependencies: ["ScanAdapters", "ScanCore"]),
        .testTarget(name: "LiveTests", dependencies: ["ScanAdapters", "ScanCore"]),
        .testTarget(name: "ScanOrganizerCLITests", dependencies: ["ScanOrganizerCLI", "ScanCore"]),
    ]
)
