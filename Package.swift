// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeveloperChatbot",
    // Dual packaging (honest):
    // - SPM: macOS library + executable (`swift build` / `swift test` on host).
    // - Xcode monorepo (`create_xcodeproj.py`): iOS app (iPhone, iOS 18.0).
    // Declared `.iOS("18.0")` aligns Package.swift with the Xcode iOS target only.
    // iOS app/debug validation is via Xcode/Simulator (`xcodebuild`) only — not SPM.
    // Host `swift test` / `swift build` still typecheck the macOS slice; they do NOT
    // typecheck iOS `#if os(iOS)` branches on a macOS host.
    platforms: [
        .macOS("15.0"),
        .iOS("18.0")
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
