import ProjectDescription

// The app's Tuist project lives in App/ because the repository root holds ClaudeBarKit's
// Package.swift, and Tuist maps one project per folder (tuist/tuist#4624). Generating from
// here still writes ClaudeBar.xcworkspace at the root.
//
// Every scheme is declared here: some run tests from both projects, the app's (App/) and
// ClaudeBarKit's, which Tuist generates at the root from Package.swift. The app project's
// automatic schemes are off, so none duplicates the ClaudeBar scheme.

let app: Path = "App"
let kit: Path = "."

// The app project's schemes that Tuist used to generate: what each builds and the tests it runs.
let appSchemes: [(name: String, builds: String, tests: String)] = [
    ("Domain", "Domain", "DomainTests"),
    ("Infrastructure", "Infrastructure", "InfrastructureTests"),
    ("AppTests", "AppTests", "AppTests"),
    ("AcceptanceTests", "AcceptanceTests", "AcceptanceTests"),
]

// The modules, in ClaudeBarKit. Each gets a scheme of its own name, as when they were targets
// of the app's project, so `tuist test Providers` runs ProvidersTests. Diagnostics has no tests.
let modules: [(name: String, tests: String?)] = [
    ("DataSources", "DataSourcesTests"),
    ("AWSClients", "AWSClientsTests"),
    ("Providers", "ProvidersTests"),
    ("Quotas", "QuotasTests"),
    ("Diagnostics", nil),
]

let claudeBar: Scheme = .scheme(
    name: "ClaudeBar",
    shared: true,
    buildAction: .buildAction(targets: [.project(path: app, target: "ClaudeBar")]),
    testAction: .targets(
        [
            .testableTarget(target: .project(path: app, target: "AcceptanceTests")),
            .testableTarget(target: .project(path: app, target: "DomainTests")),
            .testableTarget(target: .project(path: app, target: "InfrastructureTests")),
            .testableTarget(target: .project(path: app, target: "AppTests")),
        ] + modules.compactMap(\.tests).map { .testableTarget(target: .project(path: kit, target: $0)) },
        configuration: .debug
    ),
    runAction: .runAction(configuration: .debug, executable: .project(path: app, target: "ClaudeBar")),
    archiveAction: .archiveAction(configuration: .release),
    profileAction: .profileAction(configuration: .release, executable: .project(path: app, target: "ClaudeBar")),
    analyzeAction: .analyzeAction(configuration: .debug)
)

let workspace = Workspace(
    name: "ClaudeBar",
    projects: [app],
    schemes: [claudeBar]
        + appSchemes.map { scheme in
            .scheme(
                name: scheme.name,
                shared: true,
                buildAction: .buildAction(targets: [.project(path: app, target: scheme.builds)]),
                testAction: .targets([.testableTarget(target: .project(path: app, target: scheme.tests))], configuration: .debug)
            )
        }
        + modules.map { module in
            .scheme(
                name: module.name,
                shared: true,
                buildAction: .buildAction(targets: [.project(path: kit, target: module.name)]),
                testAction: module.tests.map { .targets([.testableTarget(target: .project(path: kit, target: $0))], configuration: .debug) }
            )
        }
)
