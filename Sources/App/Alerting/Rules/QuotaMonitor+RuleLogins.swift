import Domain

/// The seam a rule reaches a refreshed login through: `Account` is the Monitor's
/// and `RuleEngine` takes plain values, so something has to flatten one into the
/// other (CANONICAL §7 — Alerting reaches a login by its id, its lineup name, its
/// usage and its status).
extension QuotaMonitor {
    /// A refreshed login as Alerting reaches it. `usage(of:)` is what the person
    /// sees — hidden quotas already left out — so a rule never judges a quota
    /// nobody watches.
    func ruleLogin(_ login: Account) -> RuleLogin {
        RuleLogin(
            id: login.id,
            providerId: login.providerId,
            name: lineupName(of: login),
            usage: usage(of: login)
        )
    }
}