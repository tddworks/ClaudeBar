import Domain

/// The words on a quota card. An outlined theme (Pop) prints them its own
/// way: a short "left"/"used" beside the number, and the reset line's time
/// picked out in bold.
enum QuotaCardText {
    /// The word beside a quota's percentage.
    static func caption(mode: UsageDisplayMode, isOutlined: Bool) -> String {
        guard isOutlined else { return mode.displayLabel }
        return mode == .used ? "used" : "left"
    }

    /// The big number an outlined theme prints on a quota card, and the
    /// short words beside it. A balance and a capped spend print the same
    /// way a percentage does, so every headline reads as one font (#499).
    struct Headline: Equatable {
        let number: String
        let caption: String
    }

    static func headline(for quota: UsageQuota, mode: UsageDisplayMode) -> Headline {
        if let used = quota.formattedDollarUsed, let cap = quota.formattedDollarCap {
            return Headline(number: used, caption: "of \(cap)")
        }
        if let balance = quota.formattedDollarRemaining {
            return Headline(number: balance, caption: "left")
        }
        return Headline(
            number: "\(Int(quota.displayPercent(mode: mode)))%",
            caption: caption(mode: mode, isOutlined: true)
        )
    }

    /// The label over a budget card's amount: extra usage is billed by the
    /// month, an API cost is just what was spent.
    static func spentLabel(for kind: CostUsage.Kind) -> String {
        switch kind {
        case .extraUsage: "SPENT THIS MONTH"
        case .apiCost: "SPENT"
        }
    }

    /// A budget's status as a phrase under its amount ("On track"), not a badge.
    static func budgetPhrase(_ status: BudgetStatus) -> String {
        let words = status.badgeText.lowercased()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// A reset line split into its lead ("Resets in") and its time
    /// ("2h 4m"), which an outlined theme sets in bold.
    struct ResetLine: Equatable {
        let lead: String
        let time: String?

        init(_ text: String) {
            for lead in ["Resets in ", "Resets "] where text.hasPrefix(lead) {
                self.lead = String(lead.dropLast())
                self.time = String(text.dropFirst(lead.count))
                return
            }
            self.lead = text
            self.time = nil
        }

        /// The time alone, for a card too narrow for its lead.
        init(time: String) {
            self.lead = ""
            self.time = time
        }
    }
}

/// The words a quota line prints — the ring card's rows under the ring and
/// the *Bars* page's lines, which used to keep a copy each.
enum QuotaLineText {
    /// The quota's word: its compact title, or its type's name — with the
    /// login's name first when several logins need telling apart.
    static func title(_ quota: UsageQuota, login: String? = nil, shown: (String) -> String = { $0 }) -> String {
        let name = quota.compactTitle ?? quota.quotaType.displayName
        return login.map { "\(shown($0)) · \(name)" } ?? name
    }

    /// A percentage in the person's display mode; a balance as its amount.
    static func value(_ quota: UsageQuota, mode: UsageDisplayMode) -> String {
        if quota.isBalance, let dollars = quota.formattedDollarRemaining { return dollars }
        return "\(Int(quota.displayPercent(mode: mode)))%"
    }
}
