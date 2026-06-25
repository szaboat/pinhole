// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Pinhole",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "Pinhole", targets: ["Pinhole"])
    ],
    targets: [
        .executableTarget(
            name: "Pinhole",
            path: "Sources/Pinhole"
        )
    ]
)
