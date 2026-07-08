// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeveloperChatbot",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "DeveloperChatbot", targets: ["DeveloperChatbot"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "DeveloperChatbot",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "DeveloperChatbotTests",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs")
            ],
            path: "Tests"
        )
    ]
)
