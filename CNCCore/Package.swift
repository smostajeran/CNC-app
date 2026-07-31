// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CNCCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CNCCore", targets: ["CNCCore"]),
    ],
    targets: [
        .target(
            name: "CNCCore",
            path: "Sources/CNCCore"
        ),
        .testTarget(
            name: "CNCCoreTests",
            dependencies: ["CNCCore"],
            path: "Tests/CNCCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
