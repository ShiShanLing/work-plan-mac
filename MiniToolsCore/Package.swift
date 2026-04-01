// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MiniToolsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MiniToolsCore", targets: ["MiniToolsCore"]),
    ],
    targets: [
        .target(name: "MiniToolsCore"),
        .testTarget(
            name: "MiniToolsCoreTests",
            dependencies: ["MiniToolsCore"]
        ),
    ]
)
