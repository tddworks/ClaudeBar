import ProjectDescription

/// One of the Mac app's own modules, beside the App in Sources/Modules/<name>
/// (docs/architecture/MODULAR_DESIGN.md §2): its open face at the top of
/// Sources/, its implementations in Sources/Internal/, its tests in Tests/.
/// A framework of its own, so `internal` keeps Internal/ out of the App's reach.
func appModule(_ name: String, dependencies: [TargetDependency]) -> [Target] {
    [
        .target(
            name: name,
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.\(name.lowercased())",
            deploymentTargets: .macOS("15.0"),
            sources: ["../Sources/Modules/\(name)/Sources/**"],
            dependencies: dependencies + [.external(name: "Mockable")],
            settings: .settings(base: ["SWIFT_STRICT_CONCURRENCY": "complete"])
        ),
        .target(
            name: "\(name)Tests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.tddworks.claudebar.\(name.lowercased())-tests",
            deploymentTargets: .macOS("15.0"),
            sources: ["../Sources/Modules/\(name)/Tests/**"],
            dependencies: [.target(name: name)] + dependencies + [.external(name: "Mockable")],
            settings: .settings(base: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "MOCKING"])
        ),
    ]
}

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
    targets: appModule("Activity", dependencies: [
        .external(name: "Quotas"),
        .external(name: "DataSources"),
        .external(name: "Providers"),
        .external(name: "Diagnostics"),
    ]) + appModule("Alerting", dependencies: [
        .external(name: "Quotas"),
        .external(name: "DataSources"),
        .external(name: "Providers"),
        .external(name: "Monitoring"),
        .external(name: "Diagnostics"),
    ]) + appModule("LocalAPI", dependencies: [
        .external(name: "Quotas"),
        .external(name: "DataSources"),
        .external(name: "Providers"),
        .external(name: "Monitoring"),
        .external(name: "Diagnostics"),
    ]) + appModule("Storage", dependencies: [
        .external(name: "Quotas"),
        .external(name: "DataSources"),
        .external(name: "Providers"),
        .external(name: "Monitoring"),
        .external(name: "Leaderboard"),
        .external(name: "Diagnostics"),
        .target(name: "Activity"),
        .target(name: "Alerting"),
        .target(name: "LocalAPI"),
    ]) + [
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
                .external(name: "Quotas"),
                .external(name: "Diagnostics"),
                .external(name: "DataSources"),
                .external(name: "Providers"),
                .external(name: "Monitoring"),
                .external(name: "Leaderboard"),
                .external(name: "AWSClients"),
                .target(name: "Activity"),
                .target(name: "Alerting"),
                .target(name: "LocalAPI"),
                .target(name: "Storage"),
                .external(name: "Mockable"),
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
                .external(name: "Quotas"),
                .external(name: "DataSources"),
                .external(name: "Providers"),
                .external(name: "Monitoring"),
                .external(name: "Leaderboard"),
                .target(name: "Activity"),
                .target(name: "Alerting"),
                .target(name: "LocalAPI"),
                .target(name: "Storage"),
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