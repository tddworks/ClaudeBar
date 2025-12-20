// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "ClaudeBar", targets: ["ClaudeBar"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
    ],
    targets: [
        // MARK: - Domain Layer (Rich domain models, business logic, ports)
        // Uses domain-driven terminology: UsageQuota, AIProvider, QuotaMonitor
        .target(
            name: "Domain",
            dependencies: [
                .product(name: "Mockable", package: "Mockable"),
            ],
            path: "Sources/Domain",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .define("MOCKING", .when(configuration: .debug)),
            ]
        ),

        // MARK: - Infrastructure Layer (Technical implementations)
        // Uses technical terminology: PTYCommandRunner, JSONParser, FileSystem
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
            ],
            path: "Sources/Infrastructure",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),

        // MARK: - Main Application (UI directly exposes domain)
        // SwiftUI views directly use rich domain models - no ViewModel layer
        .executableTarget(
            name: "ClaudeBar",
            dependencies: [
                "Domain",
                "Infrastructure",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/App",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .define("ENABLE_SPARKLE"),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "DomainTests",
            dependencies: [
                "Domain",
                .product(name: "Mockable", package: "Mockable"),
            ],
            path: "Tests/DomainTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("Testing"),
                .define("MOCKING"),
            ]
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: [
                "Infrastructure",
                "Domain",
                .product(name: "Mockable", package: "Mockable"),
            ],
            path: "Tests/InfrastructureTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableExperimentalFeature("Testing"),
                .define("MOCKING"),
            ]
        ),
    ]
)
