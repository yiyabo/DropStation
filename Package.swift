// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DropStation",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DropStation", targets: ["DropStation"])
    ],
    targets: [
        .executableTarget(name: "DropStation")
    ]
)
