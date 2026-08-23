// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CallBridgeMac",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "callbridge",
            path: "Sources/CallBridgeMac"
        )
    ]
)
