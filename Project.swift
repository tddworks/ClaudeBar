import ProjectDescription

let project = Project(
    name: "ClaudeBar",
    options: .options(
        defaultKnownRegions: ["en"],
        developmentRegion: "en"
    ),
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
                .target(name: "Quotas"),
                .target(name: "DataSources"),
                .target(name: "Providers"),
                .external(name: "Mockable"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // MARK: - Modules (one per bounded context — docs/architecture/MODULAR_DESIGN.md)

        // Quotas — the usage model every module speaks: UsageSnapshot,
        // UsageQuota, UsageError, plans and costs. Depends on nothing.
        .target(
            name: "Quotas",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.quotas",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/Quotas/Sources/**"],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // Diagnostics — AppLog; the only module anything may import.
        .target(
            name: "Diagnostics",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.diagnostics",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/Diagnostics/Sources/**"],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // DataSources — DataSource, its definition, the closed sums and their
        // workers, and the ports for what lies outside (CLI, network, RPC).
        .target(
            name: "DataSources",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.datasources",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/DataSources/Sources/**"],
            dependencies: [
                .target(name: "Quotas"),
                .target(name: "Diagnostics"),
                .external(name: "Mockable"),
                .external(name: "SwiftTerm"),
                .external(name: "Subprocess"),
                .external(name: "SweetCookieKit"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // AWSClients — the only module that links the AWS SDK: CloudWatch
        // sums and the Bedrock price list, behind DataSources' ports.
        .target(
            name: "AWSClients",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.awsclients",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/AWSClients/Sources/**"],
            dependencies: [
                .target(name: "DataSources"),
                .target(name: "Diagnostics"),
                .external(name: "AWSCloudWatch"),
                .external(name: "AWSSTS"),
                .external(name: "AWSPricing"),
                .external(name: "AWSSDKIdentity"),
                .external(name: "AWSSSO"),
                .external(name: "AWSSSOOIDC"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        // Providers — the one Provider lifecycle, ProviderDefinition and the
        // catalog; the built-in definitions ship in its Resources.
        .target(
            name: "Providers",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.providers",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/Providers/Sources/**"],
            resources: ["Modules/Providers/Resources/**"],
            dependencies: [
                .target(name: "Quotas"),
                .target(name: "DataSources"),
                .target(name: "Diagnostics"),
                .external(name: "Mockable"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_STRICT_CONCURRENCY": "complete",
                ]
            )
        ),

        .target(
            name: "AWSClientsTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.awsclients-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/AWSClients/Tests/**"],
            dependencies: [
                .target(name: "AWSClients"),
                .target(name: "DataSources"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
                ]
            )
        ),

        .target(
            name: "DataSourcesTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.datasources-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/DataSources/Tests/**"],
            dependencies: [
                .target(name: "DataSources"),
                .target(name: "Quotas"),
                .external(name: "Mockable"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
                ]
            )
        ),

        .target(
            name: "ProvidersTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.providers-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/Providers/Tests/**"],
            dependencies: [
                .target(name: "Providers"),
                .target(name: "DataSources"),
                .target(name: "Quotas"),
                .external(name: "Mockable"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
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
                .target(name: "Diagnostics"),
                .target(name: "DataSources"),
                .external(name: "Mockable"),
                .external(name: "SwiftTerm"),
                .external(name: "SweetCookieKit"),
                .external(name: "Subprocess"),
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
                .target(name: "Diagnostics"),
                .target(name: "DataSources"),
                .target(name: "Providers"),
                .target(name: "AWSClients"),
                .target(name: "Infrastructure"),
                .external(name: "Sparkle"),
                .external(name: "MenuBarExtraAccess"),
                .external(name: "Matrix"),
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
                .external(name: "Mockable"),
                .external(name: "AWSCloudWatch"),
                .external(name: "AWSSTS"),
                .external(name: "AWSPricing"),
                .external(name: "AWSSDKIdentity"),
                .external(name: "AWSSSO"),
                .external(name: "AWSSSOOIDC"),
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
                .target(name: "DataSources"),
                .target(name: "Diagnostics"),
                .target(name: "Domain"),
                .external(name: "Mockable"),
                .external(name: "AWSCloudWatch"),
                .external(name: "AWSSTS"),
                .external(name: "AWSPricing"),
                .external(name: "AWSSDKIdentity"),
                .external(name: "AWSSSO"),
                .external(name: "AWSSSOOIDC"),
            ],
            settings: .settings(
                base: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING",
                ]
            )
        ),

        // MARK: - App Tests
        .target(
            name: "AppTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.app-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/AppTests/**"],
            dependencies: [
                .target(name: "ClaudeBar"),
                .target(name: "Domain"),
                .target(name: "Infrastructure"),
            ]
        ),

        // MARK: - Acceptance Tests (BDD - Outer Loop)
        .target(
            name: "AcceptanceTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.acceptance-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["Tests/AcceptanceTests/**"],
            dependencies: [
                .target(name: "Domain"),
                .target(name: "Infrastructure"),
                .target(name: "DataSources"),
                .target(name: "Providers"),
                .external(name: "Mockable"),
                .external(name: "AWSCloudWatch"),
                .external(name: "AWSSTS"),
                .external(name: "AWSPricing"),
                .external(name: "AWSSDKIdentity"),
                .external(name: "AWSSSO"),
                .external(name: "AWSSSOOIDC"),
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
                    .testableTarget(target: .target("AcceptanceTests")),
                    .testableTarget(target: .target("DomainTests")),
                    .testableTarget(target: .target("InfrastructureTests")),
                    .testableTarget(target: .target("AppTests")),
                    .testableTarget(target: .target("DataSourcesTests")),
                    .testableTarget(target: .target("AWSClientsTests")),
                    .testableTarget(target: .target("ProvidersTests")),
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