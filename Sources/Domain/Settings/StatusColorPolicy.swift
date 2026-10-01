import Foundation

/// An sRGB color as three 0...1 components. Persisted as `#RRGGBB`.
public struct RGBColorValue: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public var hexString: String {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// WCAG 2.x relative luminance (sRGB linearized, then weighted).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21, order-independent. Text needs 4.5:1.
    public static func contrastRatio(_ a: RGBColorValue, _ b: RGBColorValue) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

extension RGBColorValue: Codable {
    public init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let value = RGBColorValue(hex: hex) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a #RRGGBB color, got \(hex)"
            ))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// Typical menu bar backgrounds; the real bar is a translucent blur over the
/// wallpaper, so these are representative, not exact.
public enum MenuBarSurface {
    public static let light = RGBColorValue(hex: "#ECECEE")!
    public static let dark = RGBColorValue(hex: "#1F1F22")!
}

public enum ColorAppearance {
    case light
    case dark
}

public struct StatusPalette: Hashable, Sendable {
    public let healthy: RGBColorValue
    public let warning: RGBColorValue
    public let critical: RGBColorValue
    public let depleted: RGBColorValue

    public init(healthy: RGBColorValue, warning: RGBColorValue, critical: RGBColorValue, depleted: RGBColorValue) {
        self.healthy = healthy
        self.warning = warning
        self.critical = critical
        self.depleted = depleted
    }

    public subscript(status: QuotaStatus) -> RGBColorValue {
        switch status {
        case .healthy: healthy
        case .warning: warning
        case .critical: critical
        case .depleted: depleted
        }
    }

    /// Every value clears 4.5:1 on `MenuBarSurface.light` (locked by test).
    public static let highContrastLight = StatusPalette(
        healthy: RGBColorValue(hex: "#17703A")!,
        warning: RGBColorValue(hex: "#8A5A00")!,
        critical: RGBColorValue(hex: "#B81F1F")!,
        depleted: RGBColorValue(hex: "#7A1414")!
    )

    /// Every value clears 4.5:1 on `MenuBarSurface.dark` (locked by test).
    /// Depleted shifts pink: no darker red passes on a dark ground while
    /// staying distinguishable from critical.
    public static let highContrastDark = StatusPalette(
        healthy: RGBColorValue(hex: "#00D959")!,
        warning: RGBColorValue(hex: "#F2BF33")!,
        critical: RGBColorValue(hex: "#FF5C5C")!,
        depleted: RGBColorValue(hex: "#FF8FA3")!
    )

    public static func highContrast(for appearance: ColorAppearance) -> StatusPalette {
        appearance == .dark ? highContrastDark : highContrastLight
    }
}

/// The user's own status colors; nil defers to High Contrast, then the theme.
public struct StatusColorOverrides: Codable, Hashable, Sendable {
    public var healthy: RGBColorValue?
    public var warning: RGBColorValue?
    public var critical: RGBColorValue?
    public var depleted: RGBColorValue?

    public init(healthy: RGBColorValue? = nil, warning: RGBColorValue? = nil,
                critical: RGBColorValue? = nil, depleted: RGBColorValue? = nil) {
        self.healthy = healthy
        self.warning = warning
        self.critical = critical
        self.depleted = depleted
    }

    public static let none = StatusColorOverrides()

    public var isEmpty: Bool {
        healthy == nil && warning == nil && critical == nil && depleted == nil
    }

    public subscript(status: QuotaStatus) -> RGBColorValue? {
        get {
            switch status {
            case .healthy: healthy
            case .warning: warning
            case .critical: critical
            case .depleted: depleted
            }
        }
        set {
            switch status {
            case .healthy: healthy = newValue
            case .warning: warning = newValue
            case .critical: critical = newValue
            case .depleted: depleted = newValue
            }
        }
    }
}

/// Precedence: per-status user override, then High Contrast when enabled,
/// then nil (the theme's own color).
public struct StatusColorPolicy: Hashable, Sendable {
    public var overrides: StatusColorOverrides
    public var highContrastEnabled: Bool

    public init(overrides: StatusColorOverrides, highContrastEnabled: Bool) {
        self.overrides = overrides
        self.highContrastEnabled = highContrastEnabled
    }

    public static let `default` = StatusColorPolicy(overrides: .none, highContrastEnabled: false)

    /// False means the theme can be used unwrapped.
    public var isActive: Bool {
        highContrastEnabled || !overrides.isEmpty
    }

    public func color(for status: QuotaStatus, appearance: ColorAppearance) -> RGBColorValue? {
        if let override = overrides[status] { return override }
        if highContrastEnabled { return StatusPalette.highContrast(for: appearance)[status] }
        return nil
    }
}
