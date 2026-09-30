// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SSHManager",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SSHManager",
            path: "Sources/SSHManager"
        ),
        .testTarget(
            name: "SSHManagerTests",
            dependencies: ["SSHManager"],
            path: "Tests/SSHManagerTests"
        ),
    ]
)
