// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Xeno",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.11.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.6.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.9.0"),
    ],
    targets: [
        .target(
            name: "Xeno",
            dependencies: ["NIO", "NIOHTTP2", "NIOSSL"]),
        .testTarget(
            name: "XenoTests",
            dependencies: ["Xeno"]),
    ]
)
