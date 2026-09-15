// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipTiny",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "ClipTiny",
            path: "Sources/ClipTiny"
        ),
        .testTarget(name: "ClipTinyTests", dependencies: ["ClipTiny"])
    ]
)
