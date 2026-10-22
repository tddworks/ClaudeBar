import Foundation
import Domain

/// The Monitor's reads, as the local API asks them. It never refreshes and
/// never decides — it reads what the screens read (statuses under the
/// person's policy, the forecast, an explicit ask of the usage history) and
/// builds the JSON contract out of the answers. Read on the main actor,
/// where the Monitor's state lives.
@MainActor
struct MonitorLocalAPIReading: LocalAPIReading {
    private let monitor: QuotaMonitor

    init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    /// `GET /status` — the one line: the worst quota across the watched
    /// logins, under the person's policy.
    func statusSummary() -> StatusSummary {
        StatusSummary(status: monitor.overallStatus, lowest: lowestQuota(), providers: monitor.lineup.count)
    }

    /// `GET /providers` — every watched login: what it last said, its status,
    /// which login has the most left, which one new sessions start with.
    /// One product at a time, in the lineup's order.
    func providersReport() -> ProvidersReport {
        var order: [String] = []
        var byProduct: [String: [Account]] = [:]
        for login in monitor.lineup {
            if byProduct[login.providerId] == nil { order.append(login.providerId) }
            byProduct[login.providerId, default: []].append(login)
        }
        let providers = order.map { id -> ProviderReport in
            let logins = byProduct[id] ?? []
            let product = logins.first.flatMap { monitor.product(of: $0) }
            return ProviderReport(
                id: id,
                name: product?.definition.profile.name ?? id,
                logins: logins.map { loginReport($0, product: product) }
            )
        }
        return ProvidersReport(providers: providers)
    }

    /// `GET /forecast` — every quota that has a forecast line, the card's
    /// hourglass row as data. A quota without a forecast is left out, as its
    /// card leaves the line out.
    func forecastReport() -> ForecastReport {
        var forecasts: [ForecastLine] = []
        for login in monitor.lineup {
            guard let snapshot = monitor.usage(of: login) else { continue }
            for quota in snapshot.quotas {
                guard let forecast = quota.forecast,
                      let line = ForecastLine(
                        forecast: forecast, quota: quota,
                        provider: productName(of: login), login: login.id,
                        loginName: monitor.lineupName(of: login)
                      )
                else { continue }
                forecasts.append(line)
            }
        }
        return ForecastReport(forecasts: forecasts)
    }

    /// `GET /usage/days?n=` — per login, day by day. An explicit ask, like a
    /// popover opening: each watched login's history is read here and never
    /// in the background; a login with no history has no series.
    func usageDays(count: Int) async -> UsageDaysReport {
        let calendar = DataSources.calendar()
        var logins: [LoginDaySeries] = []
        for login in monitor.lineup {
            guard let history = login.usageHistory else { continue }
            let days = await history.days(in: .last(count, endingOn: Date(), calendar: calendar))
            logins.append(LoginDaySeries(
                id: login.id,
                name: monitor.lineupName(of: login),
                days: days.stats.map { DayUsage(stat: $0, knowsCost: days.knowsCost, calendar: calendar) }
            ))
        }
        return UsageDaysReport(days: count, logins: logins)
    }

    // MARK: - The reads, one question at a time

    /// The quota about to run out first — the least share left across every
    /// quota that has one. A balance with no ceiling never stands for it.
    private func lowestQuota() -> LowestQuota? {
        var lowest: (quota: UsageQuota, share: Double, login: Account)?
        for login in monitor.lineup {
            guard let snapshot = monitor.usage(of: login) else { continue }
            for quota in snapshot.quotas where LocalAPIContract.hasShare(quota) {
                let share = LocalAPIContract.share(of: quota) ?? 0
                if lowest == nil || share < lowest!.share {
                    lowest = (quota, share, login)
                }
            }
        }
        guard let lowest else { return nil }
        return LowestQuota(
            quota: lowest.quota,
            provider: productName(of: lowest.login),
            login: lowest.login.id,
            name: monitor.lineupName(of: lowest.login)
        )
    }

    /// One login, as the Accounts card prints it.
    private func loginReport(_ login: Account, product: Provider?) -> LoginReport {
        let snapshot = monitor.usage(of: login)
        return LoginReport(
            id: login.id,
            name: monitor.lineupName(of: login),
            status: monitor.status(of: login) ?? .healthy,
            best: product?.accounts.best?.id == login.id,
            inUse: product?.inUse?.isInUse(login) == true,
            plan: snapshot?.accountTier?.badgeText,
            source: login.answeredByLabel,
            updatedAt: snapshot?.capturedAt,
            quotas: (snapshot?.quotas ?? []).map { QuotaReport(quota: $0) }
        )
    }

    /// The product's name, or its id when no product stands behind the login.
    private func productName(of login: Account) -> String {
        monitor.product(of: login)?.definition.profile.name ?? login.providerId
    }
}
