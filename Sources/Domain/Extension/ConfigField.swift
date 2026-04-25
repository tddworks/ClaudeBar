import Foundation

/// A configuration field declared in an extension manifest.
/// Extension authors use these to define what settings their probe scripts need.
/// Values are injected as environment variables (CLAUDEBAR_*) when probes execute.
public struct ConfigField: Sendable, Equatable, Codable {
    public let id: String
    public let label: String
    public let type: ConfigFieldType
    public let required: Bool
    public let defaultValue: String?
    public let placeholder: String?
    public let helpText: String?
    public let options: [String]?

    public init(
        id: String,
        label: String,
        type: ConfigFieldType,
        required: Bool = false,
        defaultValue: String? = nil,
        placeholder: String? = nil,
        helpText: String? = nil,
        options: [String]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.placeholder = placeholder
        self.helpText = helpText
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case id, label, type, required, placeholder, helpText, options
        case defaultValue = "default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(ConfigFieldType.self, forKey: .type)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        helpText = try container.decodeIfPresent(String.self, forKey: .helpText)
        options = try container.decodeIfPresent([String].self, forKey: .options)
    }

    // MARK: - Computed Properties

    /// Whether this field holds sensitive data (stored in UserDefaults, not JSON).
    public var isSecret: Bool {
        type == .secret
    }

    /// The environment variable name injected into probe scripts.
    /// Converts the field id to CLAUDEBAR_UPPER_SNAKE_CASE.
    /// Examples: "apiKey" → "CLAUDEBAR_API_KEY", "base-url" → "CLAUDEBAR_BASE_URL"
    public var environmentVariableName: String {
        let snake = id.replacingOccurrences(of: "-", with: "_")
        var result = ""
        for (index, char) in snake.enumerated() {
            if char.isUppercase {
                if index > 0 {
                    result.append("_")
                }
                result.append(char.lowercased())
            } else {
                result.append(char)
            }
        }
        return "CLAUDEBAR_\(result.uppercased())"
    }

    /// Returns the stored value if present, otherwise the default value.
    public func effectiveValue(stored: String?) -> String? {
        stored ?? defaultValue
    }
}

// MARK: - Field Types

public enum ConfigFieldType: String, Sendable, Equatable, Codable {
    case string
    case secret
    case number
    case toggle
    case choice
    case path
}
