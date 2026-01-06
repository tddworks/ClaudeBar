#if ENABLE_SPARKLE
import Sparkle
import SwiftUI

/// Delegate to receive update notifications from Sparkle
private class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate, @unchecked Sendable {
    weak var wrapper: SparkleUpdater?

    /// Whether to include beta channel updates
    var includeBetaUpdates: Bool = false

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        let wrapper = self.wrapper
        Task { @MainActor in
            wrapper?.setUpdateAvailable(version: version)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let wrapper = self.wrapper
        Task { @MainActor in
            wrapper?.clearUpdateAvailable()
        }
    }

    /// Return the set of allowed channels for updates
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        if includeBetaUpdates {
            return Set(["beta"])
        } else {
            return Set()
        }
    }
}

/// User driver delegate to handle gentle reminders for background apps
private class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    /// We implement our own gentle reminder via the update badge indicator
    var supportsGentleScheduledUpdateReminders: Bool { true }
}

/// A wrapper around SPUUpdater for SwiftUI integration.
/// This class manages the Sparkle update lifecycle and provides
/// observable properties for UI binding.
@MainActor
@Observable
final class SparkleUpdater {
    /// The underlying Sparkle updater controller (nil if bundle is invalid)
    private var controller: SPUStandardUpdaterController?

    /// Delegate to receive update notifications
    private var updaterDelegate: SparkleUpdaterDelegate?

    /// User driver delegate to handle gentle reminders
    private var userDriverDelegate: SparkleUserDriverDelegate?

    /// Observer for beta updates setting changes
    nonisolated(unsafe) private var betaSettingObserver: NSObjectProtocol?

    /// Whether an update check is currently in progress
    private(set) var isCheckingForUpdates = false

    /// Whether a new update is available
    private(set) var isUpdateAvailable = false

    /// The version string of the available update
    private(set) var availableVersion: String?

    /// Whether the updater is available (bundle is properly configured)
    var isAvailable: Bool {
        controller != nil
    }

    /// Whether updates can be checked (updater is configured and ready)
    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    /// The date of the last update check
    var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    init() {
        // Check if we're in a proper app bundle
        if Self.isProperAppBundle() {
            // Create delegate to receive update notifications
            let delegate = SparkleUpdaterDelegate()
            self.updaterDelegate = delegate

            // Create user driver delegate for gentle reminders support
            let userDriver = SparkleUserDriverDelegate()
            self.userDriverDelegate = userDriver

            // Normal app bundle - initialize Sparkle with delegates
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: delegate,
                userDriverDelegate: userDriver
            )

            // Set back reference for delegate callbacks
            delegate.wrapper = self

            // Configure allowed channels based on settings
            updateAllowedChannels()

            // Listen for beta updates setting changes
            betaSettingObserver = NotificationCenter.default.addObserver(
                forName: .betaUpdatesSettingChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateAllowedChannels()
                }
            }
        } else {
            // Debug/development build - Sparkle won't work without proper bundle
            print("SparkleUpdater: Not running from app bundle, updater disabled")
        }
    }

    deinit {
        if let observer = betaSettingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Updates the allowed channels based on user settings
    private func updateAllowedChannels() {
        guard let delegate = updaterDelegate else { return }

        let receiveBeta = AppSettings.shared.receiveBetaUpdates
        delegate.includeBetaUpdates = receiveBeta
    }

    /// Manually check for updates
    func checkForUpdates() {
        guard let controller = controller, controller.updater.canCheckForUpdates else {
            return
        }
        // Bring app to front so update window appears above other windows
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Check for updates in the background (no UI unless update found)
    func checkForUpdatesInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    /// Called by delegate when an update is found
    fileprivate func setUpdateAvailable(version: String) {
        isUpdateAvailable = true
        availableVersion = version
    }

    /// Called by delegate when no update is found
    fileprivate func clearUpdateAvailable() {
        isUpdateAvailable = false
        availableVersion = nil
    }

    /// Check if running from a proper .app bundle
    private static func isProperAppBundle() -> Bool {
        let bundle = Bundle.main

        // Check bundle path ends with .app
        guard bundle.bundlePath.hasSuffix(".app") else {
            return false
        }

        // Check required keys exist
        guard let info = bundle.infoDictionary,
              info["CFBundleIdentifier"] != nil,
              info["CFBundleVersion"] != nil,
              info["SUFeedURL"] != nil else {
            return false
        }

        return true
    }
}

// MARK: - SwiftUI Environment

/// Environment key for accessing the SparkleUpdater
private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SparkleUpdater? = nil
}

extension EnvironmentValues {
    @MainActor
    var sparkleUpdater: SparkleUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }
}
#endif
