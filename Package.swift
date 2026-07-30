// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipTiny",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipTiny",
            path: "Sources/ClipTiny"
        )
    ]
)
