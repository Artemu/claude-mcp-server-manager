// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MCPManager",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MCPManager",
            path: "Sources/MCPManager"
        )
    ]
)
