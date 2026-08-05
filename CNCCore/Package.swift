// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CNCCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "CNCCore", targets: ["CNCCore"]),
        .executable(name: "ta4demo", targets: ["TA4Demo"]),
    ],
    targets: [
        .target(
            name: "CNCCore",
            path: "Sources/CNCCore"
        ),
        .executableTarget(
            name: "TA4Demo",
            dependencies: ["CNCCore"],
            path: "Sources/TA4Demo"
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
