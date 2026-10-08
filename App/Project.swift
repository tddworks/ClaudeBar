import ProjectDescription

let project = Project(
    name: "ClaudeBar",
    options: .options(
        // Every scheme is declared in ../Workspace.swift; an automatic one for the app target
        // would duplicate the workspace's ClaudeBar scheme.
        automaticSchemesOptions: .disabled,
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
            sources: ["../Sources/Domain/**"],
            dependencies: [
                .external(name: "Quotas"),
                .external(name: "DataSources"),
                .external(name: "Providers"),
                .external(name: "Mockable"),
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
            sources: ["../Sources/Infrastructure/**"],
            dependencies: [
                .target(name: "Domain"),
                .external(name: "Diagnostics"),
                .external(name: "DataSources"),
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
            infoPlist: .file(path: "../Sources/App/Info.plist"),
            sources: ["../Sources/App/**"],
            resources: [
                "../Sources/App/Resources/**",
            ],
            entitlements: .file(path: "../Sources/App/entitlements.plist"),
            dependencies: [
                .target(name: "Domain"),
                .external(name: "Diagnostics"),
                .external(name: "DataSources"),
                .external(name: "Providers"),
                .external(name: "AWSClients"),
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
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.tddworks.claudebar",
                ],
                debug: [
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG ENABLE_SPARKLE",
                    // A dev or test copy must never share the installed app's
                    // bundle ID: Sparkle's installer watches only the first
                    // running app with it, so a running debug build can break
                    // the installed app's update handshake (issue #450).
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.tddworks.claudebar.debug",
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
            sources: ["../Tests/DomainTests/**"],
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
            sources: ["../Tests/InfrastructureTests/**"],
            dependencies: [
                .target(name: "Infrastructure"),
                .external(name: "DataSources"),
                .external(name: "Diagnostics"),
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
            sources: ["../Tests/AppTests/**"],
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
            sources: ["../Tests/AcceptanceTests/**"],
            dependencies: [
                .target(name: "Domain"),
                .target(name: "Infrastructure"),
                .external(name: "DataSources"),
                .external(name: "Providers"),
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
    ]
    // The ClaudeBar scheme and the modules' schemes are in ../Workspace.swift: they also run
    // tests from the ClaudeBarKit project, which a project's own scheme can't reference.
)