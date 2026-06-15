// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LoopsAIChatSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "LoopsAIChatSDK",
            targets: ["LoopsAIChatSDK"]
        )
    ],
    targets: [
        .target(
            name: "LoopsAIChatSDK",
            dependencies: [],
            path: "Sources/LoopsAIChatSDK"
        ),
        .testTarget(
            name: "LoopsAIChatSDKTests",
            dependencies: ["LoopsAIChatSDK"],
            path: "Tests/LoopsAIChatSDKTests"
        )
    ]
)
