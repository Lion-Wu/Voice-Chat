import Foundation

struct ModelThinkingOption: Codable, Equatable, Hashable, Sendable, Identifiable {
    static let off = ModelThinkingOption(rawValue: "off", normalizedKey: "off")
    static let on = ModelThinkingOption(rawValue: "on", normalizedKey: "on")
    static let none = ModelThinkingOption(rawValue: "none", normalizedKey: "off")
    static let minimal = ModelThinkingOption(rawValue: "minimal", normalizedKey: "minimal")
    static let low = ModelThinkingOption(rawValue: "low", normalizedKey: "low")
    static let medium = ModelThinkingOption(rawValue: "medium", normalizedKey: "medium")
    static let high = ModelThinkingOption(rawValue: "high", normalizedKey: "high")
    static let xhigh = ModelThinkingOption(rawValue: "xhigh", normalizedKey: "xhigh")
    static let max = ModelThinkingOption(rawValue: "max", normalizedKey: "max")
    static let ultra = ModelThinkingOption(rawValue: "ultra", normalizedKey: "ultra")

    let rawValue: String
    private let normalizedKey: String

    var id: String { rawValue }

    var isDisabled: Bool {
        self == .off || self == .none
    }

    var isEffortLevel: Bool {
        !isDisabled && self != .on
    }

    var displayName: String {
        if self == .off || self == .none {
            return NSLocalizedString("Off", comment: "Thinking control option")
        }
        if self == .on {
            return NSLocalizedString("On", comment: "Thinking control option")
        }
        if self == .minimal {
            return NSLocalizedString("Minimal", comment: "Thinking effort option")
        }
        if self == .low {
            return NSLocalizedString("Low", comment: "Thinking effort option")
        }
        if self == .medium {
            return NSLocalizedString("Medium", comment: "Thinking effort option")
        }
        if self == .high {
            return NSLocalizedString("High", comment: "Thinking effort option")
        }
        if self == .xhigh {
            return NSLocalizedString("Extra High", comment: "Thinking effort option")
        }
        if self == .max {
            return NSLocalizedString("Max", comment: "Thinking effort option")
        }
        if self == .ultra {
            return NSLocalizedString("Ultra", comment: "Thinking effort option")
        }
        return rawValue
    }

    init(rawValue: String, normalizedKey: String? = nil) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed
        self.normalizedKey = normalizedKey ?? Self.normalizedKey(for: trimmed)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self.normalized(rawValue) ?? ModelThinkingOption(rawValue: rawValue)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func == (lhs: ModelThinkingOption, rhs: ModelThinkingOption) -> Bool {
        lhs.normalizedKey == rhs.normalizedKey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedKey)
    }

    static func normalized(_ raw: String) -> ModelThinkingOption? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = normalizedKey(for: trimmed)
        switch normalized {
        case "off", "disabled", "disable", "false":
            return .off
        case "none", "no_reasoning":
            return .off
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
        case "ultra":
            return .ultra
        default:
            return ModelThinkingOption(rawValue: trimmed, normalizedKey: normalized)
        }
    }

    private static func normalizedKey(for raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "off", "none", "no_reasoning", "disabled", "disable", "false":
            return "off"
        case "on", "enabled", "enable", "true", "auto", "dynamic":
            return "on"
        default:
            return normalized
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
    let supported_efforts: [String]?
    let supportedEfforts: [String]?
    let default_effort: String?
    let defaultEffort: String?
    let mandatory: Bool?
    let default_enabled: Bool?
    let defaultEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case allowed_options
        case allowedOptions
        case options
        case values
        case defaultValue = "default"
        case default_option
        case supported_efforts
        case supportedEfforts
        case default_effort
        case defaultEffort
        case mandatory
        case default_enabled
        case defaultEnabled
    }

    init(
        allowed_options: [String]? = nil,
        allowedOptions: [String]? = nil,
        options: [String]? = nil,
        values: [String]? = nil,
        defaultValue: String? = nil,
        default_option: String? = nil,
        supported_efforts: [String]? = nil,
        supportedEfforts: [String]? = nil,
        default_effort: String? = nil,
        defaultEffort: String? = nil,
        mandatory: Bool? = nil,
        default_enabled: Bool? = nil,
        defaultEnabled: Bool? = nil
    ) {
        self.allowed_options = allowed_options
        self.allowedOptions = allowedOptions
        self.options = options
        self.values = values
        self.defaultValue = defaultValue
        self.default_option = default_option
        self.supported_efforts = supported_efforts
        self.supportedEfforts = supportedEfforts
        self.default_effort = default_effort
        self.defaultEffort = defaultEffort
        self.mandatory = mandatory
        self.default_enabled = default_enabled
        self.defaultEnabled = defaultEnabled
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            allowed_options = try container.decodeIfPresent([String].self, forKey: .allowed_options)
            allowedOptions = try container.decodeIfPresent([String].self, forKey: .allowedOptions)
            options = try container.decodeIfPresent([String].self, forKey: .options)
            values = try container.decodeIfPresent([String].self, forKey: .values)
            defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
            default_option = try container.decodeIfPresent(String.self, forKey: .default_option)
            supported_efforts = try container.decodeIfPresent([String].self, forKey: .supported_efforts)
            supportedEfforts = try container.decodeIfPresent([String].self, forKey: .supportedEfforts)
            default_effort = try container.decodeIfPresent(String.self, forKey: .default_effort)
            defaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultEffort)
            mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory)
            default_enabled = try container.decodeIfPresent(Bool.self, forKey: .default_enabled)
            defaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled)
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
            supported_efforts = nil
            supportedEfforts = nil
            default_effort = nil
            defaultEffort = nil
            mandatory = nil
            default_enabled = nil
            defaultEnabled = nil
            return
        }
        if let rawOption = try? singleValue.decode(String.self) {
            allowed_options = [rawOption]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = rawOption
            default_option = nil
            supported_efforts = nil
            supportedEfforts = nil
            default_effort = nil
            defaultEffort = nil
            mandatory = nil
            default_enabled = nil
            defaultEnabled = nil
            return
        }
        if let supported = try? singleValue.decode(Bool.self) {
            allowed_options = supported ? ["off", "on"] : ["off"]
            allowedOptions = nil
            options = nil
            values = nil
            defaultValue = supported ? "on" : "off"
            default_option = nil
            supported_efforts = nil
            supportedEfforts = nil
            default_effort = nil
            defaultEffort = nil
            mandatory = nil
            default_enabled = supported
            defaultEnabled = nil
            return
        }

        allowed_options = nil
        allowedOptions = nil
        options = nil
        values = nil
        defaultValue = nil
        default_option = nil
        supported_efforts = nil
        supportedEfforts = nil
        default_effort = nil
        defaultEffort = nil
        mandatory = nil
        default_enabled = nil
        defaultEnabled = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(allowed_options, forKey: .allowed_options)
        try container.encodeIfPresent(allowedOptions, forKey: .allowedOptions)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encodeIfPresent(values, forKey: .values)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encodeIfPresent(default_option, forKey: .default_option)
        try container.encodeIfPresent(supported_efforts, forKey: .supported_efforts)
        try container.encodeIfPresent(supportedEfforts, forKey: .supportedEfforts)
        try container.encodeIfPresent(default_effort, forKey: .default_effort)
        try container.encodeIfPresent(defaultEffort, forKey: .defaultEffort)
        try container.encodeIfPresent(mandatory, forKey: .mandatory)
        try container.encodeIfPresent(default_enabled, forKey: .default_enabled)
        try container.encodeIfPresent(defaultEnabled, forKey: .defaultEnabled)
    }

    func asThinkingCapability() -> ModelThinkingCapability? {
        asThinkingCapability(requestParameter: nil)
    }

    func asThinkingCapability(requestParameter: ModelThinkingRequestParameter?) -> ModelThinkingCapability? {
        let rawEfforts = supported_efforts ?? supportedEfforts ?? []
        if !rawEfforts.isEmpty {
            var rawOptions: [String] = []
            let parsedEfforts = rawEfforts.compactMap(ModelThinkingOption.normalized)
            let enabledEfforts = parsedEfforts.filter { !$0.isDisabled }
            if mandatory != true {
                rawOptions.append("off")
            }
            rawOptions.append(contentsOf: enabledEfforts.map(\.rawValue))
            let parsedOptions = rawOptions.compactMap(ModelThinkingOption.normalized)
            let defaultEnabled = default_enabled ?? defaultEnabled
            let parsedExplicitDefault = [default_effort, defaultEffort, defaultValue, default_option]
                .compactMap { $0 }
                .compactMap(ModelThinkingOption.normalized)
                .first
            let parsedDefault: ModelThinkingOption?
            if defaultEnabled == false, let disabledOption = parsedOptions.first(where: \.isDisabled) {
                parsedDefault = disabledOption
            } else {
                parsedDefault = parsedExplicitDefault
            }
            guard !parsedOptions.isEmpty else { return nil }
            return ModelThinkingCapability(
                options: parsedOptions,
                defaultOption: parsedDefault,
                requestParameter: requestParameter
            )
        }

        let rawOptions = allowed_options ?? allowedOptions ?? options ?? values ?? []
        let parsedOptions = rawOptions.compactMap(ModelThinkingOption.normalized)
        let parsedDefault = [defaultValue, default_option, default_effort, defaultEffort]
            .compactMap { $0 }
            .compactMap(ModelThinkingOption.normalized)
            .first
        if parsedOptions.isEmpty, let enabled = default_enabled ?? defaultEnabled ?? mandatory {
            let options: [ModelThinkingOption] = mandatory == true ? [.on] : [.off, .on]
            return ModelThinkingCapability(
                options: options,
                defaultOption: enabled ? .on : .off,
                requestParameter: requestParameter
            )
        }
        guard !parsedOptions.isEmpty else { return nil }
        return ModelThinkingCapability(
            options: parsedOptions,
            defaultOption: parsedDefault,
            requestParameter: requestParameter
        )
    }
}
