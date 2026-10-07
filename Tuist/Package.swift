// swift-tools-version: 6.0
import PackageDescription


#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "ClaudeBar",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        // Exposes MenuBarExtra's underlying NSStatusItem so the menu-bar label
        // can be driven imperatively (AppKit), surviving the SwiftUI label
        // freeze after system sleep (issue #192).
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.0"),
        // Dot-matrix loaders. Custom licence: commercial use is granted, but
        // republishing the components as a reusable library is not — fine for
        // consuming it here, so long as the source is never vendored.
        .package(url: "https://github.com/mana-am/matrix-swift", from: "0.2.0"),
    ]
)
