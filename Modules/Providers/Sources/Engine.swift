import DataSources
import Foundation
import Synchronization

/// Everything that touches this Mac, built once by the composition root and
/// the same for every provider (TARGET_ARCHITECTURE §10). A definition uses
/// only what its cases ask for: a `cloudWatch` fetch gets the cloud ports, a
/// lookup that says `loginShell` gets the shell, a definition that declares
/// `guestPasses` gets them run. Nothing here names a provider.
public struct Engine: Sendable {
    /// The cloud's metrics and prices, made the first time a definition that
    /// reads the cloud is made.
    public typealias CloudPorts = @Sendable () -> (any CloudWatchClient, any PriceCatalog)
    /// The runner for the guest-passes capability, at the declaring
    /// definition's CLI location (read each time, so a change applies at once).
    public typealias GuestPassRunner = @Sendable (_ cli: @escaping @Sendable () -> String) -> any GuestPassSource

    public let settings: any MultiAccountSettingsRepository
    public let vault: (any SecretVault)?
    public let loginsInUse: (any LoginsInUse)?
    public let environment: @Sendable (String) -> String?
    public let loginShell: (@Sendable (String) -> String?)?
    public let guestPasses: GuestPassRunner?
    private let cloud: Cloud?

    public init(settings: any MultiAccountSettingsRepository,
                vault: (any SecretVault)? = nil,
                loginsInUse: (any LoginsInUse)? = nil,
                environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
                loginShell: (@Sendable (String) -> String?)? = nil,
                cloud: CloudPorts? = nil,
                guestPasses: GuestPassRunner? = nil) {
        self.settings = settings
        self.vault = vault
        self.loginsInUse = loginsInUse
        self.environment = environment
        self.loginShell = loginShell
        self.cloud = cloud.map(Cloud.init)
        self.guestPasses = guestPasses
    }

    /// The cloud ports, made once on first use; nil without a cloud.
    func cloudPorts() -> (any CloudWatchClient, any PriceCatalog)? {
        cloud?.ports()
    }

    /// Makes the cloud ports once, whoever asks first.
    private final class Cloud: Sendable {
        private let make: CloudPorts
        private let made = Mutex<(any CloudWatchClient, any PriceCatalog)?>(nil)

        init(_ make: @escaping CloudPorts) {
            self.make = make
        }

        func ports() -> (any CloudWatchClient, any PriceCatalog) {
            made.withLock { made in
                if let made { return made }
                let ports = make()
                made = ports
                return ports
            }
        }
    }
}

extension ProviderFactory {
    /// A provider of every definition, in the order given, on one engine.
    @MainActor
    public static func make(_ definitions: [ProviderDefinition], engine: Engine) -> [Provider] {
        definitions.map { make($0, engine: engine) }
    }

    /// A provider of the definition on the engine: its logins from settings,
    /// the cloud only when it reads the cloud, guest passes only when it
    /// declares them. A definition from outside the bundle becomes findable
    /// by its lineup id.
    @MainActor
    public static func make(_ definition: ProviderDefinition, engine: Engine) -> Provider {
        if definition.profile.origin != .builtIn { register(custom: definition) }
        let id = definition.id
        let readsCloud = definition.dataSources.contains { if case .cloudWatch = $0.fetch { true } else { false } }
        let cloud = readsCloud ? engine.cloudPorts() : nil
        let settings = engine.settings
        let cli = definition.cli ?? id
        let guestPasses = definition.guestPassPlans.flatMap { plans in engine.guestPasses.map { run in
            GuestPasses(source: run({ settings.cliPath(forProvider: id) ?? cli }), plans: plans)
        } }
        return make(definition, settings: settings, accounts: settings.accounts(forProvider: id), secrets: engine.vault,
                    guestPasses: guestPasses, environment: engine.environment, loginShell: engine.loginShell,
                    cloudWatch: cloud?.0, priceCatalog: cloud?.1, loginsInUse: engine.loginsInUse)
    }
}
