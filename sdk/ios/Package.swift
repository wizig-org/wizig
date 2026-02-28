// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wizig",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "Wizig", targets: ["Wizig"]),
    ],
    targets: [
        .target(
            name: "Wizig",
            path: "Sources/Wizig"
        ),
    ]
)
