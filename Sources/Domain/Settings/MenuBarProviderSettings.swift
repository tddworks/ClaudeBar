import Foundation

/// Display choices belonging to one provider. An empty primary key follows its first quota.
public struct MenuBarProviderSettings: Codable, Sendable, Equatable {
    public var primaryQuotaKey: String
    public var secondaryQuotaKey: String
    public var stacked: Bool
    public var stackedSize: String

    public init(primaryQuotaKey: String = "", secondaryQuotaKey: String = "",
                stacked: Bool = false, stackedSize: String = "small") {
        self.primaryQuotaKey = primaryQuotaKey
        self.secondaryQuotaKey = secondaryQuotaKey
        self.stacked = stacked
        self.stackedSize = stackedSize
    }
}
