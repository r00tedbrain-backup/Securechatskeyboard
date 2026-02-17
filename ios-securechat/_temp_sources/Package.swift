// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SecureChatKeyboard",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/LRUCache.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Shared", dependencies: ["LRUCache"]),
    ]
)
