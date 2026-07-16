// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodebaseExplorerApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "CodebaseExplorerApp",
            targets: ["CodebaseExplorerApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CodebaseExplorerApp",
            dependencies: ["SecureFileAccessC"],
            path: "Sources/CodebaseExplorerApp"
        ),
        .target(
            name: "SecureFileAccessC",
            path: "Sources/SecureFileAccessC",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "CodebaseExplorerAppTests",
            dependencies: ["CodebaseExplorerApp"],
            path: "Tests/CodebaseExplorerAppTests"
        ),
    ]
)
