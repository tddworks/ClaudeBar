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
        // Kit — the Swift face of ClaudeBarKit, the Kotlin SDK that holds everything but the UI
        // (MODULAR_DESIGN §5), and the only target that links it; scripts/build-kotlin.sh builds it.
        .target(
            name: "Kit",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.tddworks.claudebar.kitface",
            deploymentTargets: .macOS("15.0"),
            sources: ["Modules/Kit/Sources/**"],
            dependencies: [
                .xcframework(path: "ClaudeBarKit/build/XCFrameworks/release/ClaudeBarKit.xcframework"),
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
                // The built-in provider definitions, read by ClaudeBarCore.start(definitions:).
                .folderReference(path: "ClaudeBarKit/definitions"),
            ],
            entitlements: .file(path: "Sources/App/entitlements.plist"),
            dependencies: [
                .target(name: "Kit"),
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
            sources: ["Tests/AppTests/**"],
            dependencies: [
                .target(name: "ClaudeBar"),
                .target(name: "Kit"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "ClaudeBar",
            shared: true,
            buildAction: .buildAction(targets: ["ClaudeBar"]),
            testAction: .targets(
                [
                    .testableTarget(target: .target("AppTests")),
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