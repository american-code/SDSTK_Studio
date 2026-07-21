// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "MBExpertServer",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "MBExpertServer", path: "Sources/MBExpertServer")
    ]
)
