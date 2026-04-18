// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Cinder64",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "Cinder64"
        ),
        .testTarget(
            name: "Cinder64Tests",
            dependencies: ["Cinder64"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
