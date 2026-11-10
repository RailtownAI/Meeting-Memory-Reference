// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhiteboardCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "WhiteboardCore",
            targets: ["WhiteboardCore"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/RailtownAI/Railtracks-swift",
            exact: "0.1.15"
        ),
        .package(url: "https://github.com/RailtownAI/railengine-retrieval-swift-sdk", exact: "1.0.0"),
        .package(url: "https://github.com/RailtownAI/railengine-ingest-swift-sdk", exact: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(
            url: "https://github.com/RailtownAI/railtown-swift-logger.git",
            .upToNextMinor(from: "0.3.1")
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "WhiteboardCore",
            dependencies: [
                .product(name: "RailtracksSwift", package: "Railtracks-swift"),
                .product(name: "Railengine", package: "railengine-retrieval-swift-sdk"),
                .product(name: "RailengineIngest", package: "railengine-ingest-swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "RailtownLogger", package: "railtown-swift-logger"),
            ]
        ),
    ]
)
