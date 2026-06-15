import Foundation

/// Optional flow-mode feature-flag overrides forwarded to the web runtime via
/// `initConfig`. Each flag is optional: when `nil` the SDK sends
/// nothing for it and the **server-resolved agent config** decides. Set a flag
/// only to deliberately override per launch.
///
/// These also tell the host app which flows to surface as native entry points
/// (e.g. show a VTO button only when `virtualTryOnEnabled != false`).
public struct LoopsFeatureFlags: Sendable {
    public var voiceModeEnabled: Bool?
    public var speechToTextEnabled: Bool?
    public var virtualTryOnEnabled: Bool?
    public var searchEscalationEnabled: Bool?
    public var productSuggestionEnabled: Bool?
    public var outfitSuggestionEnabled: Bool?

    public init(
        voiceModeEnabled: Bool? = nil,
        speechToTextEnabled: Bool? = nil,
        virtualTryOnEnabled: Bool? = nil,
        searchEscalationEnabled: Bool? = nil,
        productSuggestionEnabled: Bool? = nil,
        outfitSuggestionEnabled: Bool? = nil
    ) {
        self.voiceModeEnabled = voiceModeEnabled
        self.speechToTextEnabled = speechToTextEnabled
        self.virtualTryOnEnabled = virtualTryOnEnabled
        self.searchEscalationEnabled = searchEscalationEnabled
        self.productSuggestionEnabled = productSuggestionEnabled
        self.outfitSuggestionEnabled = outfitSuggestionEnabled
    }

    /// No overrides — defer entirely to the server-resolved agent config.
    public static let `default` = LoopsFeatureFlags()

    /// Only the flags that were explicitly set, for merging into `initConfig`.
    /// Absent flags are omitted so the web keeps its server defaults.
    func payload() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let voiceModeEnabled { dict["voiceModeEnabled"] = voiceModeEnabled }
        if let speechToTextEnabled { dict["speechToTextEnabled"] = speechToTextEnabled }
        if let virtualTryOnEnabled { dict["virtualTryOnEnabled"] = virtualTryOnEnabled }
        if let searchEscalationEnabled { dict["searchEscalationEnabled"] = searchEscalationEnabled }
        if let productSuggestionEnabled { dict["productSuggestionEnabled"] = productSuggestionEnabled }
        if let outfitSuggestionEnabled { dict["outfitSuggestionEnabled"] = outfitSuggestionEnabled }
        return dict
    }
}
