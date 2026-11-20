import SwiftUI
import Activity

/// How ClaudeBar was started: by the person, or by Xcode to host AppTests.
///
/// Hosting tests, the app starts nothing — no providers, no Keychain, no
/// refreshes, no menu bar. A local build is ad-hoc signed, so every touch of
/// the Keychain would ask for access again, and tests would read real usage.
enum LaunchMode: Equatable {
    case menuBarApp
    case testHost

    /// Xcode names the test configuration in the host app's environment.
    init(environment: [String: String]) {
        self = environment["XCTestConfigurationFilePath"] == nil ? .menuBarApp : .testHost
    }

    static var current: LaunchMode { LaunchMode(environment: ProcessInfo.processInfo.environment) }
}

/// The entry point: the menu bar app, or an empty app while hosting tests.
@main
enum ClaudeBarMain {
    static func main() {
        switch LaunchMode.current {
        case .menuBarApp: ClaudeBarApp.main()
        case .testHost: TestHostApp.main()
        }
    }
}

/// What runs while AppTests are hosted: one scene that shows nothing.
struct TestHostApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
