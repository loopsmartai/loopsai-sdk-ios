import Foundation

/// The frozen `mode=sdk` bridge protocol (CONTRACT Part B, native channel).
///
/// The native channel (`loopsAIBridge`) uses a **typed envelope**:
/// ```jsonc
/// { "protocolVersion": 1, "type": "nativeAction", "name": "openProduct",
///   "requestId": "req_123", "payload": { /* … */ } }
/// ```
/// The iframe/embed channel keeps the legacy flat `{ action }` shape — that is a
/// separate transport the SDK never touches.
enum LoopsAIBridgeProtocol {
    /// Bump only via a coordinated web + iOS + Android update (CONTRACT change policy).
    static let version = 1

    /// Envelope `type` discriminator. Only `nativeAction` is defined in v1.
    static let messageType = "nativeAction"

    /// Web → native action names the SDK handles (CONTRACT B.2 allowlist).
    /// Anything not listed here is ignored.
    enum WebAction: String, CaseIterable {
        case ready
        case closeChat
        case openProduct
        case openModule
        case openExternalUrl
        case requestTokenRefresh
        case trackEvent              // analytics passthrough
        case respondingStateChange
        case productQuoteChanged
        case conversationActive
        case newChatStarted
        case persistSession
        case overlayOpen
        case overlayClosed
    }

    /// Native → web action names the SDK sends (CONTRACT B.3).
    enum NativeAction: String {
        case initConfig
        case initContext
        case updateContext
        case sendUserMessage
        case searchEscalation
        case startVirtualTryOn
        case startTryOnFromQuote
        case quoteProduct            // pin a product as the active quote (card above the input)
        case suggestSize
        case syncCustomerDetails
        case setWebsiteFont
        case startVoiceMode          // reserved — server-gated, no public entry point
        case setAnalyticsConsent     // host CMP consent → web A.4 consent gate
        case clearProductQuote       // clear the active quote chip
        case closeOverlays           // dispatch loopsai:close-overlays in the runtime
        case mobileStateChange       // rotation / size-class change → re-evaluate layout
    }
}

/// A decoded inbound envelope from the web runtime (native channel).
struct LoopsAIInboundMessage {
    let protocolVersion: Int
    let type: String
    let name: String
    let requestId: String?
    let payload: [String: Any]

    /// Parses the typed native-channel envelope. Returns `nil` for anything that
    /// is not a well-formed `nativeAction` envelope (legacy flat messages, other
    /// frames). The web runtime emits the typed envelope only in `mode=sdk`.
    init?(body: Any) {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String,
              type == LoopsAIBridgeProtocol.messageType,
              let name = dict["name"] as? String
        else { return nil }

        // protocolVersion is required on the typed envelope; default to current
        // for forward-tolerance if a producer omits it.
        self.protocolVersion = (dict["protocolVersion"] as? Int) ?? LoopsAIBridgeProtocol.version
        self.type = type
        self.name = name
        self.requestId = dict["requestId"] as? String
        self.payload = (dict["payload"] as? [String: Any]) ?? [:]
    }
}
