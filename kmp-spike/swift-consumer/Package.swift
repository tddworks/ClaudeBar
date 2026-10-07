// swift-tools-version:6.0
import PackageDescription

// A Swift 6 (strict concurrency) caller of the Kotlin module, standing in for the app.
let package = Package(
    name: "QuotasDemo",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(
            name: "QuotasDemo",
            dependencies: [.product(name: "ClaudeBarQuotas", package: "kmp-spike")]
        ),
    ]
)
