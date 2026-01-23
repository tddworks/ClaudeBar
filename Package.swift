// swift-tools-version: 6.2
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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.1"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
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
                .product(name: "Mockable", package: "Mockable"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                // AWS SDK for Bedrock usage monitoring
                .product(name: "AWSCloudWatch", package: "aws-sdk-swift"),
                .product(name: "AWSSTS", package: "aws-sdk-swift"),
                .product(name: "AWSPricing", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift"),
            ],
            path: "Sources/Infrastructure",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .define("MOCKING", .when(configuration: .debug)),
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
            exclude: [
                "Info.plist",
                "entitlements.plist",
            ],
            resources: [
                .process("Resources"),
            ],
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
