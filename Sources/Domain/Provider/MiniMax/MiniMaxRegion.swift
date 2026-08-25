import Foundation

/// Represents the MiniMax API region. (MiniMax API 区域设置)
/// - international: api.minimax.io / platform.minimax.io (For International Users)
/// - china: api.minimaxi.com / platform.minimaxi.com (For Users in China)
public enum MiniMaxRegion: String, Sendable, Equatable, CaseIterable {
    case international
    case china

    /// Display name for the region picker (区域显示名称)
    public var displayName: String {
        switch self {
        case .international: return "International (minimax.io)"
        case .china: return "China (minimaxi.com)"
        }
    }

    /// API base URL for coding plan remains endpoint (Coding Plan API 基础 URL)
    public var apiBaseURL: String {
        switch self {
        case .international: return "https://api.minimax.io"
        case .china: return "https://api.minimaxi.com"
        }
    }

    /// Platform URL for dashboard (平台仪表盘 URL)
    public var platformURL: String {
        switch self {
        case .international: return "https://platform.minimax.io"
        case .china: return "https://platform.minimaxi.com"
        }
    }

    /// URL to get API keys from the platform (获取 API Key 的页面 URL)
    public var apiKeysURL: URL {
        switch self {
        case .international:
            return URL(string: "https://platform.minimax.io/user-center/basic-information/interface-key")!
        case .china:
            return URL(string: "https://platform.minimaxi.com/user-center/basic-information/interface-key")!
        }
    }

    /// Dashboard URL for coding plan payment page (Coding Plan 付费页面 URL)
    public var dashboardURL: URL {
        switch self {
        case .international:
            return URL(string: "https://platform.minimax.io/user-center/payment/coding-plan")!
        case .china:
            return URL(string: "https://platform.minimaxi.com/user-center/payment/coding-plan")!
        }
    }

    /// Full API URL for the coding plan remains endpoint (Coding Plan 剩余额度 API URL)
    public var codingPlanRemainsURL: String {
        "\(apiBaseURL)/v1/token_plan/remains"
    }
}
