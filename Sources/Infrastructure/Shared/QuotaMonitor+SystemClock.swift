import Domain

public extension QuotaMonitor {
    convenience init(
        providers: any AIProviderRepository,
        alerter: (any QuotaAlerter)? = nil
    ) {
        self.init(providers: providers, alerter: alerter, clock: SystemClock())
    }
}
