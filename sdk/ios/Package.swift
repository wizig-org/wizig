// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ziggy",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Ziggy", targets: ["Ziggy"]),
    ],
    targets: [
        .target(
            name: "Ziggy",
            path: "Sources/Ziggy"
        ),
    ]
)
