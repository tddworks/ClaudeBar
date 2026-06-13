// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // SwiftTerm uses .framework to avoid tuist/tuist#9111 — Tuist 4.78.1+ duplicates
    // Metal shaders into both Sources and Resources for staticFramework SPM bundles.
    productTypes: [
        "SwiftTerm": .framework,
    ],
    targetSettings: [
        "IssueReporting": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "IssueReportingPackageSupport": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "SwiftTerm": ["EXCLUDED_SOURCE_FILE_NAMES": "Shaders.metal"],
    ]
)
#endif

let package = Package(
    name: "ClaudeBar",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        .package(url: "https://github.com/Kolos65/Mockable.git", from: "0.5.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.12.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift", exact: "1.6.99"),
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.3.0"),
        // Exposes MenuBarExtra's underlying NSStatusItem so the menu-bar label
        // can be driven imperatively (AppKit), surviving the SwiftUI label
        // freeze after system sleep (issue #192).
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
    ]
)
