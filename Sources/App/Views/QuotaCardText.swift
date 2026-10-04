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
