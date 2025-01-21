// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UserKit",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UserKit",
            targets: ["UserKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.10.0"),
        .package(url: "https://github.com/stasel/WebRTC", from: "128.0.0"),
        .package(url: "https://github.com/KaneCheshire/ShowTime", from: "2.5.3")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UserKit",
            dependencies: [
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "ShowTime", package: "ShowTime")
            ]
        ),
        .testTarget(
            name: "UserKitTests",
            dependencies: ["UserKit"]),
    ]
)
