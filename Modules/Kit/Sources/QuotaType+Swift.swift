import ClaudeBarKit

extension QuotaType {
    /// Rolling 5-hour session limit.
    public static var session: QuotaType { QuotaType.Session.shared }
    /// Rolling 7-day weekly limit.
    public static var weekly: QuotaType { QuotaType.Weekly.shared }
    /// A model's own limit ("opus", "sonnet").
    public static func modelSpecific(_ name: String) -> QuotaType { QuotaType.ModelSpecific(name: name) }
    /// A named limit ("MCP Usage", "Monthly").
    public static func timeLimit(_ name: String) -> QuotaType { QuotaType.TimeLimit(name: name) }

    public static func == (lhs: QuotaType, rhs: QuotaType) -> Bool { lhs.isEqual(rhs) }

    /// The kind of quota, to `switch` on.
    public enum Shape: Equatable, Sendable {
        case session
        case weekly
        case modelSpecific(String)
        case timeLimit(String)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .session: .session
        case .weekly: .weekly
        case .modelSpecific(let model): .modelSpecific(model.name)
        case .timeLimit(let limit): .timeLimit(limit.name)
        }
    }
}

/// Lets `QuotaType(quotaKey:)` return the subclass the key names.
public protocol QuotaKeyReadable {}
extension QuotaType: QuotaKeyReadable {}

extension QuotaKeyReadable where Self: QuotaType {
    /// The quota type a persisted key was saved from.
    public init?(quotaKey: String) {
        guard let type = QuotaType.companion.fromQuotaKey(quotaKey: quotaKey) as? Self else { return nil }
        self = type
    }
}

extension QuotaDuration {
    public static func hours(_ hours: Int) -> QuotaDuration { QuotaDuration.Hours(hours: Int32(hours)) }
    public static func days(_ days: Int) -> QuotaDuration { QuotaDuration.Days(days: Int32(days)) }

    public static func == (lhs: QuotaDuration, rhs: QuotaDuration) -> Bool { lhs.isEqual(rhs) }
}

extension StatusPolicy {
    /// Warning under 50% left, whatever the pace.
    public static var absolute: StatusPolicy { StatusPolicy.Absolute.shared }
    /// Warning only while burning faster than the sustainable pace.
    public static func paceAware(burnRateThreshold: Double) -> StatusPolicy {
        StatusPolicy.PaceAware(burnRateThreshold: burnRateThreshold)
    }

    /// The policy the burn-rate settings describe.
    public static func from(burnRateWarningEnabled: Bool, burnRateThreshold: Double) -> StatusPolicy {
        StatusPolicy.companion.from(burnRateWarningEnabled: burnRateWarningEnabled, burnRateThreshold: burnRateThreshold)
    }

    public static func == (lhs: StatusPolicy, rhs: StatusPolicy) -> Bool { lhs.isEqual(rhs) }

    public enum Shape: Equatable, Sendable {
        case absolute
        case paceAware(burnRateThreshold: Double)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .absolute: .absolute
        case .paceAware(let policy): .paceAware(burnRateThreshold: policy.burnRateThreshold)
        }
    }
}
