import ProjectDescription

let project = Project(
    name: "ClaudeBar",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
    packages: [
        .remote(url: "https://github.com/sparkle-project/Sparkle", requirement: .upToNextMajor(from: "2.8.1")),
        .remote(url: "https://github.com/Kolos65/Mockable.git", requirement: .upToNextMajor(from: "0.5.0")),
        .remote(url: "https://github.com/migueldeicaza/SwiftTerm.git", requirement: .upToNextMajor(from: "1.2.0")),
        .remote(url: "https://github.com/awslabs/aws-sdk-swift.git", requirement: .upToNextMajor(from: "1.0.0")),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "15.0",
            "ENABLE_DEBUG_DYLIB": "YES",
        ],
        debug: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG MOCKING",
            "ENABLE_DEBUG_DYLIB": "YES",
        ],
        release: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
        ]
    ),
    targets: [
        // MARK: - Domain Layer
        .target(
            name: "Domain",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.domain",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/Domain/**"],
            dependencies: [
                .package(product: "Mockable"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // MARK: - Infrastructure Layer
        .target(
            name: "Infrastructure",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.infrastructure",
            deploymentTargets: .macOS("15.0"),
            sources: ["Sources/Infrastructure/**"],
            dependencies: [
                .target(name: "Domain"),
                .package(product: "Mockable"),
                .package(product: "SwiftTerm"),
                .package(product: "AWSCloudWatch"),
                .package(product: "AWSSTS"),
                .package(product: "AWSPricing"),
                .package(product: "AWSSDKIdentity"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // MARK: - Main Application
        .target(
            name: "ClaudeBar",
            destinations: .macOS,
            product: .app,
            bundleId: "com.tddworks.claudebar",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .file(path: "Sources/App/Info.plist"),
            sources: ["Sources/App/**"],
            resources: [
                "Sources/App/Resources/**",
            ],
            entitlements: .file(path: "Sources/App/entitlements.plist"),
            dependencies: [
                .target(name: "Domain"),
                .target(name: "Infrastructure"),
                .package(product: "Sparkle"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                    "ENABLE_DEBUG_DYLIB": "YES",
                    "ENABLE_PREVIEWS": "YES",
                    "CODE_SIGN_IDENTITY": "-",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                ],
                debug: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG ENABLE_SPARKLE",
                ],
                release: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "ENABLE_SPARKLE",
                ]
            )
        ),

        // MARK: - Domain Tests
        .target(
            name: "DomainTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.domain-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/DomainTests/**"],
            dependencies: [
                .target(name: "Domain"),
                .target(name: "Infrastructure"),
                .package(product: "Mockable"),
                .package(product: "AWSCloudWatch"),
                .package(product: "AWSSTS"),
                .package(product: "AWSPricing"),
                .package(product: "AWSSDKIdentity"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
                ]
            )
        ),

        // MARK: - Infrastructure Tests
        .target(
            name: "InfrastructureTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.infrastructure-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/InfrastructureTests/**"],
            dependencies: [
                .target(name: "Infrastructure"),
                .target(name: "Domain"),
                .package(product: "Mockable"),
                .package(product: "AWSCloudWatch"),
                .package(product: "AWSSTS"),
                .package(product: "AWSPricing"),
                .package(product: "AWSSDKIdentity"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
                ]
            )
        ),
    ],
    schemes: [
        .scheme(
            name: "ClaudeBar",
            shared: true,
            buildAction: .buildAction(targets: ["ClaudeBar"]),
            testAction: .targets(
                [
                    .testableTarget(target: .target("DomainTests")),
                    .testableTarget(target: .target("InfrastructureTests")),
                ],
                configuration: .debug
            ),
            runAction: .runAction(configuration: .debug, executable: .target("ClaudeBar")),
            archiveAction: .archiveAction(configuration: .release),
            profileAction: .profileAction(configuration: .release, executable: .target("ClaudeBar")),
            analyzeAction: .analyzeAction(configuration: .debug)
        ),
    ]
)