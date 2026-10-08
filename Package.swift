// swift-tools-version: 6.0
import PackageDescription

// ClaudeBarKit: ClaudeBar's modules as one Swift package, at the repository root so a client
// can depend on this repo by URL (docs/architecture/MODULAR_DESIGN.md §10). The Mac app stays
// a Tuist target and consumes these products through Tuist/Package.swift.
//
// Each module is also its own product, so the app's targets keep depending on exactly the
// modules they import. On Windows only what builds there today is declared; §10's phases
// widen it.

// The generated mocks exist in debug builds and tests (Mockable's `#if MOCKING`).
let mocking: [SwiftSetting] = [.define("MOCKING", .when(configuration: .debug))]

let mockable: Target.Dependency = .product(name: "Mockable", package: "Mockable")

#if os(macOS)
let package = Package(
    name: "ClaudeBarKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeBarKit", targets: ["Quotas", "Diagnostics", "DataSources", "Providers", "AWSClients"]),
        .library(name: "Quotas", targets: ["Quotas"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "DataSources", targets: ["DataSources"]),
        .library(name: "Providers", targets: ["Providers"]),
        .library(name: "AWSClients", targets: ["AWSClients"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.12.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift", exact: "1.6.99"),
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
    ],
    targets: [
        // Quotas — the usage model every module speaks: UsageSnapshot, UsageQuota,
        // UsageError, plans and costs. Depends on nothing.
        .target(name: "Quotas", path: "Modules/Quotas/Sources"),
        .testTarget(name: "QuotasTests", dependencies: ["Quotas"], path: "Modules/Quotas/Tests"),

        // Diagnostics — AppLog; the only module anything may import.
        .target(name: "Diagnostics", path: "Modules/Diagnostics/Sources"),

        // DataSources — DataSource, its definition, the closed sums and their workers,
        // and the ports for what lies outside (CLI, network, RPC).
        .target(
            name: "DataSources",
            dependencies: [
                "Quotas",
                "Diagnostics",
                mockable,
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ],
            path: "Modules/DataSources/Sources",
            swiftSettings: mocking
        ),
        .testTarget(
            name: "DataSourcesTests",
            dependencies: ["DataSources", "Quotas", mockable],
            path: "Modules/DataSources/Tests",
            swiftSettings: mocking
        ),

        // AWSClients — the only module that links the AWS SDK: CloudWatch sums and the
        // Bedrock price list, behind DataSources' ports.
        .target(
            name: "AWSClients",
            dependencies: [
                "DataSources",
                "Diagnostics",
                .product(name: "AWSCloudWatch", package: "aws-sdk-swift"),
                .product(name: "AWSSTS", package: "aws-sdk-swift"),
                .product(name: "AWSPricing", package: "aws-sdk-swift"),
                .product(name: "AWSSDKIdentity", package: "aws-sdk-swift"),
                .product(name: "AWSSSO", package: "aws-sdk-swift"),
                .product(name: "AWSSSOOIDC", package: "aws-sdk-swift"),
            ],
            path: "Modules/AWSClients/Sources"
        ),
        .testTarget(
            name: "AWSClientsTests",
            dependencies: ["AWSClients", "DataSources"],
            path: "Modules/AWSClients/Tests",
            swiftSettings: mocking
        ),

        // Providers — the one Provider lifecycle, ProviderDefinition and the catalog; the
        // built-in definitions ship in its Resources, flat in the bundle (ProviderFactory).
        .target(
            name: "Providers",
            dependencies: ["Quotas", "DataSources", "Diagnostics", mockable],
            path: "Modules/Providers",
            exclude: ["Tests"],
            sources: ["Sources"],
            resources: [.process("Resources")],
            swiftSettings: mocking
        ),
        .testTarget(
            name: "ProvidersTests",
            dependencies: ["Providers", "DataSources", "Quotas", mockable],
            path: "Modules/Providers/Tests",
            swiftSettings: mocking
        ),
    ]
)
#else
// What builds on Windows today (§10 phase 0): Quotas, and a probe that a @Mockable port
// and its mock work there, since Quotas declares no ports.
let package = Package(
    name: "ClaudeBarKit",
    products: [
        .library(name: "ClaudeBarKit", targets: ["Quotas"]),
        .library(name: "Quotas", targets: ["Quotas"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "Quotas", path: "Modules/Quotas/Sources"),
        .testTarget(name: "QuotasTests", dependencies: ["Quotas"], path: "Modules/Quotas/Tests"),
        .testTarget(
            name: "MockableProbe",
            dependencies: [mockable],
            path: ".github/windows/MockableProbe",
            swiftSettings: [.define("MOCKING")]
        ),
    ]
)
#endif
