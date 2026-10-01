import Domain

extension QuotaMonitor {
    /// Every quota window the enabled providers are currently reporting.
    ///
    /// A pure read of observable state and nothing else, so it can be called
    /// from inside an `ObservationRenderSync` read closure and have every
    /// property it touches tracked: `enabledProviders`, each provider's
    /// `snapshot`, and the quotas hanging off it. Nothing here caches, filters
    /// on a clock, or short circuits, because a property this function skips is
    /// a property observation never registers, and a quota that changed
    /// afterwards would never reach the phone.
    ///
    /// It lives in the App layer rather than on `QuotaMonitor` itself because
    /// this is the boundary that flattens main actor isolated providers into the
    /// `Sendable` readings `NotifyPayloadBuilder` takes. Being `@MainActor` by
    /// inheritance is exactly right: the caller is a driver on the main actor.
    func notifyReadings() -> [NotifyQuotaReading] {
        enabledProviders.flatMap { provider in
            (provider.snapshot?.quotas ?? []).map { quota in
                NotifyQuotaReading(
                    providerId: provider.id,
                    providerName: provider.name,
                    quota: quota
                )
            }
        }
    }
}
