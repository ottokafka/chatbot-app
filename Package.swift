// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeveloperChatbot",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(name: "DeveloperChatbotCore", targets: ["DeveloperChatbotCore"]),
        .executable(name: "DeveloperChatbot", targets: ["DeveloperChatbot"])
    ],
    dependencies: [
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git", branch: "main")
    ],
    targets: [
        .target(
            name: "DeveloperChatbotCore",
            dependencies: [
                .product(name: "FSRS", package: "swift-fsrs")
            ],
            path: "Sources",
            exclude: ["App.swift"],
            resources: [
                .process("EssentialVocab"),
                .process("LifePath")
            ]
        ),
        .executableTarget(
            name: "DeveloperChatbot",
            dependencies: ["DeveloperChatbotCore"],
            path: "App"
        ),
        .testTarget(
            name: "DeveloperChatbotTests",
            dependencies: [
                "DeveloperChatbotCore",
                .product(name: "FSRS", package: "swift-fsrs")
            ],
            path: "Tests"
        )
    ]
)
