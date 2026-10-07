// swift-tools-version:6.0
import PackageDescription

let packageName = "ClaudeBarQuotas"

let package = Package(
    name: packageName,
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        ),
    ],
    targets: [
        .binaryTarget(
            name: packageName,
            path: "./quotas/build/XCFrameworks/debug/\(packageName).xcframework"
        )
        ,
    ]
)