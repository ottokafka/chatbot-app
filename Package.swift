// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeveloperChatbot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DeveloperChatbot", targets: ["DeveloperChatbot"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DeveloperChatbot",
            dependencies: [],
            path: "Sources"
        )
    ]
)
