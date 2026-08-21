// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LockTodoNoteShared",
    defaultLocalization: "en",
    // macOS is listed only so the logic tests run in seconds via `swift test`;
    // the shipped product is iOS-only.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LockTodoNoteShared", targets: ["LockTodoNoteShared"])
    ],
    targets: [
        .target(name: "LockTodoNoteShared"),
        .testTarget(
            name: "LockTodoNoteSharedTests",
            dependencies: ["LockTodoNoteShared"]
        ),
    ]
)
