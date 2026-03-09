// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentHubBuildServer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "agenthub-build-server", targets: ["AgentHubBuildServer"]),
    ],
    targets: [
        .executableTarget(
            name: "AgentHubBuildServer",
            path: "Sources"
        ),
        .testTarget(
            name: "AgentHubBuildServerTests",
            dependencies: ["AgentHubBuildServer"],
            path: "Tests"
        ),
    ]
)
