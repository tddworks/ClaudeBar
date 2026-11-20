import Domain

public extension QuotaMonitor {
    convenience init(
        providers: Providers,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider(),
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.init(
            providers: providers,
            clock: SystemClock(),
            settingsRepository: settingsRepository,
            powerStateProvider: powerStateProvider,
            statusPolicy: statusPolicy
        )
    }
}
