import Quotas
import Foundation

/// What a mapping script returns.
struct ScriptOutput: Decodable {
    struct Quota: Decodable {
        let type: QuotaKind
        let name: String?
        /// Exactly one measure: the old percentage or money, optionally of a ceiling.
        let left: Left
        /// Epoch seconds.
        let resetsAt: Double?
        let resetText: String?
        let windowSeconds: Double?
        /// The account or source it belongs to, when a report holds several.
        let group: String?

        private enum CodingKeys: String, CodingKey {
            case type, name, percentRemaining, left, resetsAt, resetText, windowSeconds, group
        }

        private struct MoneyLeft: Decodable {
            let money: Money
            let of: Money?
            let currency: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(QuotaKind.self, forKey: .type)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            let percent = try container.decodeIfPresent(Double.self, forKey: .percentRemaining)
            let money = try container.decodeIfPresent(MoneyLeft.self, forKey: .left)
            switch (percent, money) {
            case (let percent?, nil): left = .share(percent)
            case (nil, let money?):
                let currency = money.currency ?? "USD"
                guard !currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DecodingError.dataCorruptedError(forKey: .left, in: container, debugDescription: "Empty currency")
                }
                left = .money(Quotas.Money(money.money.value, currency: currency),
                              of: money.of.map { Quotas.Money($0.value, currency: currency) })
            default:
                throw DecodingError.dataCorruptedError(forKey: .left, in: container,
                                                       debugDescription: "A quota must contain exactly one of percentRemaining or left")
            }
            resetsAt = try container.decodeIfPresent(Double.self, forKey: .resetsAt)
            resetText = try container.decodeIfPresent(String.self, forKey: .resetText)
            windowSeconds = try container.decodeIfPresent(Double.self, forKey: .windowSeconds)
            group = try container.decodeIfPresent(String.self, forKey: .group)
        }
    }

    struct Cost: Decodable {
        struct Line: Decodable {
            let label: String
            let used: Money
            let detail: String?
        }

        let kind: CostRule.Kind?
        /// Decimal strings keep money exact; numbers are accepted too.
        let used: Money
        let limit: Money?
        let apiDurationSeconds: Double?
        let resetsAt: Double?
        let resetText: String?
        let lines: [Line]?
    }

    struct Account: Decodable {
        let email: String?
        let organization: String?
        let loginMethod: String?
    }

    /// `"12.50"` or `12.5`, read as an exact `Decimal` from its text.
    struct Money: Decodable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let text: String
            if let string = try? container.decode(String.self) {
                text = string
            } else {
                text = String(try container.decode(Double.self))
            }
            guard text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an amount: \(text)")
            }
            self.value = value
        }
    }

    /// A line under a group with nothing to measure — "No usage reported".
    struct Note: Decodable {
        let group: String
        let text: String
        /// The row's own name, unique in the report — the group's, unless said.
        let label: String?
    }

    let quotas: [Quota]?
    let notes: [Note]?
    let plan: String?
    let cost: Cost?
    let account: Account?
    let error: ErrorRef?

    func snapshot(providerId: String, capturedAt: Date) throws -> UsageSnapshot {
        if let error { throw error.usageError }
        let quotas = (quotas ?? []).compactMap { quota -> UsageQuota? in
            guard let type = JSONMapper.quotaType(quota.type, name: quota.name) else { return nil }
            return UsageQuota(
                left: quota.left,
                quotaType: type,
                providerId: providerId,
                resetsAt: quota.resetsAt.map { Date(timeIntervalSince1970: $0) },
                resetText: quota.resetText,
                windowDuration: quota.windowSeconds,
                group: quota.group
            )
        }
        let costUsage = cost.map { cost in
            CostUsage(
                totalCost: cost.used.value,
                budget: cost.limit?.value,
                apiDuration: cost.apiDurationSeconds ?? 0,
                providerId: providerId,
                kind: cost.kind == .extraUsage ? .extraUsage : .apiCost,
                capturedAt: capturedAt,
                resetsAt: cost.resetsAt.map { Date(timeIntervalSince1970: $0) },
                resetText: cost.resetText,
                lines: (cost.lines ?? []).map { CostLine(label: $0.label, amount: $0.used.value, detail: $0.detail) }
            )
        }
        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: capturedAt,
            accountEmail: account?.email,
            accountOrganization: account?.organization,
            loginMethod: account?.loginMethod,
            accountTier: plan.map(Self.tier),
            costUsage: costUsage,
            extensionMetrics: notes.flatMap { notes in
                notes.isEmpty ? nil : notes.map { ExtensionMetric(label: $0.label ?? $0.group, value: $0.text, unit: "", group: $0.group) }
            }
        )
    }

    /// The well-known tiers by name; anything else is a badge as written.
    static func tier(_ plan: String) -> AccountTier {
        switch plan {
        case "claudeMax": .claudeMax
        case "claudePro": .claudePro
        case "claudeApi": .claudeApi
        default: .custom(plan)
        }
    }
}
