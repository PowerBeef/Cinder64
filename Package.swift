// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cinder64",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .target(
            name: "Cinder64BridgeABI",
            path: "Sources/Cinder64BridgeABI",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Cinder64",
            dependencies: ["Cinder64BridgeABI"]
        ),
        .testTarget(
            name: "Cinder64Tests",
            dependencies: ["Cinder64", "Cinder64BridgeABI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
