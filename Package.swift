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

// swift-crypto: CryptoKit's API on every platform, and CryptoKit itself on Apple platforms,
// so the Mac's hashes and signatures don't change (§10).
let crypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto")

// The C libraries, one pinned copy each on every platform (§10 "The porting surface"):
// what can be a library is a library, not a platform fact. Vendor/ is never edited by
// hand; scripts/bump-vendor.sh is the one way a version changes.
let vendored: [Target] = [
    // QuickJS (quickjs-ng): the one engine every mapping script runs in, without its
    // libc, so a script reaches no file, network or process.
    .target(name: "CQuickJS", path: "Vendor/CQuickJS", exclude: ["VERSION", "LICENSE"], sources: ["quickjs-amalgam.c"]),
    // SQLite: the one reader of another app's own database. Loading an extension is
    // compiled out; nothing here may run code a database names. A definition's SQL
    // reads as it did on the Mac's own SQLite: double-quoted strings and the math
    // functions, as Apple builds it.
    .target(
        name: "CSQLite",
        path: "Vendor/CSQLite",
        exclude: ["VERSION", "LICENSE"],
        sources: ["sqlite3.c"],
        cSettings: [
            .define("SQLITE_OMIT_LOAD_EXTENSION"),
            .define("SQLITE_DQS", to: "3"),
            .define("SQLITE_ENABLE_MATH_FUNCTIONS"),
        ]
    ),
]

#if os(macOS)
let package = Package(
    name: "ClaudeBarKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeBarKit", targets: ["Quotas", "Diagnostics", "DataSources", "Providers", "Leaderboard", "AWSClients"]),
        .library(name: "Quotas", targets: ["Quotas"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "DataSources", targets: ["DataSources"]),
        .library(name: "Providers", targets: ["Providers"]),
        .library(name: "Leaderboard", targets: ["Leaderboard"]),
        .library(name: "AWSClients", targets: ["AWSClients"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.12.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift", exact: "1.6.99"),
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "6.0.0"),
    ],
    targets: vendored + [
        // Quotas — the usage model every module speaks: UsageSnapshot, UsageQuota,
        // UsageError, plans and costs. Depends on nothing.
        .target(name: "Quotas", path: "Modules/Quotas/Sources"),
        .testTarget(name: "QuotasTests", dependencies: ["Quotas"], path: "Modules/Quotas/Tests"),

        // Diagnostics — AppLog; the only module anything may import. Each line goes to the
        // platform's sinks: OSLog on the Mac, and the file log everywhere.
        .target(name: "Diagnostics", path: "Modules/Diagnostics/Sources"),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"], path: "Modules/Diagnostics/Tests"),

        // DataSources — DataSource, its definition, the closed sums and their workers,
        // and the ports for what lies outside (CLI, network, RPC).
        .target(
            name: "DataSources",
            dependencies: [
                "Quotas",
                "Diagnostics",
                "CQuickJS",
                "CSQLite",
                mockable,
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                crypto,
            ],
            path: "Modules/DataSources/Sources",
            swiftSettings: mocking
        ),
        .testTarget(
            name: "DataSourcesTests",
            dependencies: ["DataSources", "Quotas", "CSQLite", mockable],
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
            dependencies: ["Quotas", "DataSources", "Diagnostics", mockable, crypto],
            path: "Modules/Providers",
            exclude: ["Tests"],
            sources: ["Sources"],
            resources: [.process("Resources")],
            swiftSettings: mocking
        ),
        .testTarget(
            name: "ProvidersTests",
            dependencies: ["Providers", "DataSources", "Quotas", "CSQLite", mockable, crypto],
            path: "Modules/Providers/Tests",
            swiftSettings: mocking
        ),

        // Leaderboard — the membership, its days and their signing, the board as last read,
        // and the ports for the board's server and where the key is kept. `vectors.json`,
        // which the server shares, is read by the tests from beside them.
        .target(
            name: "Leaderboard",
            dependencies: ["Quotas", "Diagnostics", "DataSources", mockable, crypto],
            path: "Modules/Leaderboard/Sources",
            swiftSettings: mocking
        ),
        .testTarget(
            name: "LeaderboardTests",
            dependencies: ["Leaderboard", "DataSources", "Quotas", mockable, crypto],
            path: "Modules/Leaderboard/Tests",
            exclude: ["vectors.json"],
            swiftSettings: mocking
        ),
    ]
)
#else
// What builds on Windows and Linux today (§10 phases 0–2 and 6): Quotas, Diagnostics,
// DataSources, Providers and Leaderboard. SwiftTerm's core builds everywhere and carries
// the Terminal port; SweetCookieKit and the AWS SDK are the Mac's.
let package = Package(
    name: "ClaudeBarKit",
    products: [
        .library(name: "ClaudeBarKit", targets: ["Quotas", "Diagnostics", "DataSources", "Providers", "Leaderboard"]),
        .library(name: "Quotas", targets: ["Quotas"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "DataSources", targets: ["DataSources"]),
        .library(name: "Providers", targets: ["Providers"]),
        .library(name: "Leaderboard", targets: ["Leaderboard"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "6.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.12.0"),
    ],
    targets: vendored + [
        .target(name: "Quotas", path: "Modules/Quotas/Sources"),
        .testTarget(name: "QuotasTests", dependencies: ["Quotas"], path: "Modules/Quotas/Tests"),
        .target(name: "Diagnostics", path: "Modules/Diagnostics/Sources"),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics"], path: "Modules/Diagnostics/Tests"),
        .target(
            name: "DataSources",
            dependencies: [
                "Quotas",
                "Diagnostics",
                "CQuickJS",
                "CSQLite",
                mockable,
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                crypto,
            ],
            path: "Modules/DataSources/Sources",
            swiftSettings: mocking
        ),
        .testTarget(
            name: "DataSourcesTests",
            dependencies: ["DataSources", "Quotas", "CSQLite", mockable],
            path: "Modules/DataSources/Tests",
            swiftSettings: mocking
        ),
        .target(
            name: "Providers",
            dependencies: ["Quotas", "DataSources", "Diagnostics", mockable, crypto],
            path: "Modules/Providers",
            exclude: ["Tests"],
            sources: ["Sources"],
            resources: [.process("Resources")],
            swiftSettings: mocking
        ),
        .testTarget(
            name: "ProvidersTests",
            dependencies: ["Providers", "DataSources", "Quotas", "CSQLite", mockable, crypto],
            path: "Modules/Providers/Tests",
            swiftSettings: mocking
        ),
        .target(
            name: "Leaderboard",
            dependencies: ["Quotas", "Diagnostics", "DataSources", mockable, crypto],
            path: "Modules/Leaderboard/Sources",
            swiftSettings: mocking
        ),
        .testTarget(
            name: "LeaderboardTests",
            dependencies: ["Leaderboard", "DataSources", "Quotas", mockable, crypto],
            path: "Modules/Leaderboard/Tests",
            exclude: ["vectors.json"],
            swiftSettings: mocking
        ),
    ]
)
#endif
