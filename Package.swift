// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xctest-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "xctest-cli", targets: ["XCTestCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
    ],
    targets: [
        .executableTarget(
            name: "XCTestCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/XCTestCLI"
        ),
    ]
)
