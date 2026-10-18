import Domain

public extension QuotaMonitor {
    convenience init(
        providers: Providers,
        alerter: (any QuotaAlerter)? = nil,
        settingsRepository: (any ProviderSettingsRepository)? = nil,
        powerStateProvider: (any PowerStateProvider)? = SystemPowerStateProvider(),
        statusPolicy: @escaping @MainActor () -> StatusPolicy = { .absolute }
    ) {
        self.init(
            providers: providers,
            alerter: alerter,
            clock: SystemClock(),
            settingsRepository: settingsRepository,
            powerStateProvider: powerStateProvider,
            statusPolicy: statusPolicy
        )
    }
}
