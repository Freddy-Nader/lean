// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "lean",
    platforms: [.macOS("15.4")],
    targets: [
        .target(name: "LeanKit", path: "Sources/LeanKit"),
        .executableTarget(name: "Lean", dependencies: ["LeanKit"], path: "Sources/Lean"),
        .testTarget(name: "LeanKitTests", dependencies: ["LeanKit"], path: "Tests/LeanKitTests"),
    ]
)
