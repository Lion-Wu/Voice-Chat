import Foundation

enum ModelThinkingOption: String, Codable, CaseIterable, Sendable, Identifiable {
    case off
    case on
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    var id: String { rawValue }

    var isDisabled: Bool {
        self == .off || self == .none
    }

    var isEffortLevel: Bool {
        switch self {
        case .minimal, .low, .medium, .high, .xhigh, .max:
            return true
        case .off, .on, .none:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .off, .none:
            return NSLocalizedString("Off", comment: "Thinking control option")
        case .on:
            return NSLocalizedString("On", comment: "Thinking control option")
        case .minimal:
            return NSLocalizedString("Minimal", comment: "Thinking effort option")
        case .low:
            return NSLocalizedString("Low", comment: "Thinking effort option")
        case .medium:
            return NSLocalizedString("Medium", comment: "Thinking effort option")
        case .high:
            return NSLocalizedString("High", comment: "Thinking effort option")
        case .xhigh:
            return NSLocalizedString("Extra High", comment: "Thinking effort option")
        case .max:
            return NSLocalizedString("Max", comment: "Thinking effort option")
        }
    }

    static func normalized(_ raw: String) -> ModelThinkingOption? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "off", "disabled", "disable", "false":
            return .off
        case "none", "no_reasoning":
            return ModelThinkingOption.none
        case "on", "enabled", "enable", "true", "auto", "dynamic":
            return .on
        case "minimal", "minimum":
            return .minimal
        case "low":
            return .low
        case "medium", "normal", "default":
            return .medium
        case "high":
            return .high
        case "xhigh", "extra_high", "extrahigh":
            return .xhigh
        case "max", "maximum":
            return .max
        default:
            return nil
        }
    }
}

enum ModelThinkingRequestParameter: String, Codable, CaseIterable, Sendable {
    case reasoningEffort = "reasoning_effort"
    case reasoning
    case thinking
}

struct ModelThinkingCapability: Codable, Equatable, Sendable {
    var options: [ModelThinkingOption]
    var defaultOption: ModelThinkingOption?
    var requestParameter: ModelThinkingRequestParameter?

    static let compatibleReasoningEffort = ModelThinkingCapability(
        options: [.off, .minimal, .low, .medium, .high, .xhigh],
        defaultOption: .off,
        requestParameter: nil
    )

    init(
        options: [ModelThinkingOption],
        defaultOption: ModelThinkingOption? = nil,
        requestParameter: ModelThinkingRequestParameter? = nil
    ) {
        var unique: [ModelThinkingOption] = []
        for option in options where !unique.contains(option) {
            unique.append(option)
        }
        self.options = unique
        if let defaultOption, unique.contains(defaultOption) {
            self.defaultOption = defaultOption
        } else {
            self.defaultOption = nil
        }
        self.requestParameter = requestParameter
    }

    var enabledOptions: [ModelThinkingOption] {
        options.filter { !$0.isDisabled }
    }

    var disabledOption: ModelThinkingOption? {
        options.first(where: \.isDisabled)
    }

    var supportsToggle: Bool {
        disabledOption != nil && !enabledOptions.isEmpty
    }

    var supportsEffortSelection: Bool {
        options.filter(\.isEffortLevel).count > 1
    }

    var isConfigurable: Bool {
        supportsToggle || supportsEffortSelection
    }

    var defaultSelection: ModelThinkingOption? {
        if let defaultOption, options.contains(defaultOption) {
            return defaultOption
        }
        if supportsEffortSelection {
            return options.contains(.medium) ? .medium : enabledOptions.first
        }
        if supportsToggle {
            return disabledOption ?? enabledOptions.first
        }
        return nil
    }

    func normalizedSelection(_ option: ModelThinkingOption?) -> ModelThinkingOption? {
        guard let option, options.contains(option) else {
            return defaultSelection
        }
        return option
    }

    func toggledSelection(from option: ModelThinkingOption?) -> ModelThinkingOption? {
        let current = normalizedSelection(option)
        if current?.isDisabled == true {
            if let defaultOption, !defaultOption.isDisabled, options.contains(defaultOption) {
                return defaultOption
            }
            return enabledOptions.first
        }
        return disabledOption
    }

    func withRequestParameter(_ requestParameter: ModelThinkingRequestParameter?) -> ModelThinkingCapability {
        ModelThinkingCapability(
            options: options,
            defaultOption: defaultOption,
            requestParameter: requestParameter
        )
    }
}

struct ModelThinkingCapabilityDescriptor: Codable, Equatable, Sendable {
    let allowed_options: [String]?
    let allowedOptions: [String]?
    let options: [String]?
    let values: [String]?
    let defaultValue: String?
    let default_option: String?

    private enum CodingKeys: String, CodingKey {
        case allowed_options
        case allowedOptions
        case options
        case values
        case defaultValue = "default"
        case default_option
    }

    init(
        allowed_options: [String]? = nil,
        allowedOptions: [String]? = nil,
        options: [String]? = nil,
        values: [String]? = nil,
        defaultValue: String? = nil,
        default_option: String? = nil
    ) {
        self.allowed_options = allowed_options
        self.allowedOptions = allowedOptions
        self.options = options
        self.values = values
        self.defaultValue = defaultValue
        self.default_option = default_option
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            allowed_options = try container.decodeIfPresent([String].self, forKey: .allowed_options)
            allowedOptions = try container.decodeIfPresent([String].self, forKey: .allowedOptions)
            options = try container.decodeIfPresent([String].self, forKey: .options)
            values = try container.decodeIfPresent([String].self, forKey: .values)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            default_option = try container.decodeIfPresent(String.self, forKey: .default_option)
            return
        }

        let singleValue = try decoder.singleValueContainer()
        if let rawOptions = try? singleValue.decode([String].self) {
            allowed_options = rawOptions
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = nil
            default_option = nil
            return
        }
        if let rawOption = try? singleValue.decode(String.self) {
            allowed_options = [rawOption]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = rawOption
            default_option = nil
            return
        }
        if let supported = try? singleValue.decode(Bool.self) {
            allowed_options = supported ? ["off", "on"] : ["off"]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = supported ? "on" : "off"
            default_option = nil
            return
        }

        allowed_options = nil
        allowedOptions = nil
        options = nil
        values = nil
        defaultValue = nil
        default_option = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(allowed_options, forKey: .allowed_options)
        try container.encodeIfPresent(allowedOptions, forKey: .allowedOptions)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(values, forKey: .values)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(default_option, forKey: .default_option)
    }

    func asThinkingCapability() -> ModelThinkingCapability? {
        asThinkingCapability(requestParameter: nil)
    }

    func asThinkingCapability(requestParameter: ModelThinkingRequestParameter?) -> ModelThinkingCapability? {
        let rawOptions = allowed_options ?? allowedOptions ?? options ?? values ?? []
        let parsedOptions = rawOptions.compactMap(ModelThinkingOption.normalized)
        let parsedDefault = [defaultValue, default_option]
            .compactMap { $0 }
            .compactMap(ModelThinkingOption.normalized)
            .first
        guard !parsedOptions.isEmpty else { return nil }
        return ModelThinkingCapability(
            options: parsedOptions,
            defaultOption: parsedDefault,
            requestParameter: requestParameter
        )
    }
}
