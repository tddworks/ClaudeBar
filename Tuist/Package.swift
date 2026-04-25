// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    productTypes: [:],
    targetSettings: [
        "IssueReporting": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "IssueReportingPackageSupport": ["SWIFT_PACKAGE_NAME": "xctest-dynamic-overlay"],
        "SwiftTerm": [
            "EXCLUDED_SOURCE_FILE_NAMES": "Shaders.metal",
            "MACOSX_DEPLOYMENT_TARGET": "12.0",
        ],
        "SweetCookieKit": ["MACOSX_DEPLOYMENT_TARGET": "12.0"],
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
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.6.43"),
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.3.0"),
    ]
)