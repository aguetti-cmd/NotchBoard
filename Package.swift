// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchBoard",
    platforms: [.macOS(.v15)],
    targets: [
        // Pure logic: parsing, decoding, geometry, formatting. No AppKit.
        .target(name: "NotchBoardCore"),
        // The menu bar app: panel, services, SwiftUI views.
        .executableTarget(
            name: "NotchBoard",
            dependencies: ["NotchBoardCore"]
        ),
        .testTarget(
            name: "NotchBoardCoreTests",
            dependencies: ["NotchBoardCore"]
        ),
    ]
)
