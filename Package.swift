// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRune",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PRune", targets: ["PRune"]),
    ],
    targets: [
        .executableTarget(
            name: "PRune",
            path: "Sources/PRune"
        ),
    ]
)
