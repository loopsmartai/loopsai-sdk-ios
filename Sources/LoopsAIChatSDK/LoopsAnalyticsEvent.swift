import Foundation
import UIKit

/// The canonical analytics event (`schema_version "1.0"`),
/// received from the web runtime over the `trackEvent` bridge action and
/// re-dispatched natively. On mobile the SDK dictates the shape:
/// `channel` is forced to `"mobile_app"` and native context
/// (`app_version`, `device`, `os_version`) is attached.
public struct LoopsAnalyticsEvent {
    public static let schemaVersion = "1.0"
    public static let channel = "mobile_app"

    /// Canonical event name (e.g. `loops_ai_view_item_list`).
    public let event: String
    /// Always `"mobile_app"` on native.
    public let channel: String
    /// The full canonical payload (Part A envelope) with `channel` + native
    /// context applied — ready for adapters and the host callback.
    public let payload: [String: Any]

    init?(bridgePayload: [String: Any], context: LoopsAnalyticsContext) {
        // The web sends `{ event: <CanonicalEvent> }`; tolerate a bare event too.
        let raw = (bridgePayload["event"] as? [String: Any]) ?? bridgePayload
        guard let event = raw["event"] as? String else { return nil }

        var merged = raw
        merged["schema_version"] = Self.schemaVersion
        merged["channel"] = Self.channel
        for (key, value) in context.fields() where merged[key] == nil {
            merged[key] = value
        }

        self.event = event
        self.channel = Self.channel
        self.payload = merged
    }

    /// Construct a canonical native event from a **host-side** action — e.g. the
    /// host app's own commerce funnel (`add_to_cart`, `begin_checkout`,
    /// `purchase`) — mirroring the web dispatcher's `trackCanonicalEvent`. Forces
    /// `channel:"mobile_app"` + `schema_version` and attaches native context, so
    /// host events look identical to bridge-relayed ones. Deliver it with
    /// ``LoopsAnalyticsDispatcher/dispatch(_:)`` or your own adapter.
    ///
    /// - Parameters:
    ///   - event: canonical event name (e.g. `"purchase"`).
    ///   - params: event-specific fields (e.g. `ecommerce`, `value`, `currency`).
    ///   - context: native base context (app/device/os + optional identity).
    public init(
        event: String,
        params: [String: Any] = [:],
        context: LoopsAnalyticsContext = LoopsAnalyticsContext()
    ) {
        var merged = params
        merged["event"] = event
        merged["schema_version"] = Self.schemaVersion
        merged["channel"] = Self.channel
        for (key, value) in context.fields() where merged[key] == nil {
            merged[key] = value
        }
        self.event = event
        self.channel = Self.channel
        self.payload = merged
    }
}

/// Native-only base context attached to every event.
/// `app_version`/`device`/`os_version` are device facts the web can't know;
/// the identity fields ride along when known.
public struct LoopsAnalyticsContext {
    public var appVersion: String
    public var device: String
    public var osVersion: String
    public var locale: String?
    public var anonUserId: String?
    public var conversationId: String?

    public init(
        appVersion: String = LoopsAnalyticsContext.hostAppVersion,
        device: String = LoopsAnalyticsContext.deviceModel,
        osVersion: String = UIDevice.current.systemVersion,
        locale: String? = nil,
        anonUserId: String? = nil,
        conversationId: String? = nil
    ) {
        self.appVersion = appVersion
        self.device = device
        self.osVersion = osVersion
        self.locale = locale
        self.anonUserId = anonUserId
        self.conversationId = conversationId
    }

    func fields() -> [String: Any] {
        var dict: [String: Any] = [
            "app_version": appVersion,
            "device": device,
            "os_version": osVersion
        ]
        if let locale { dict["locale"] = locale }
        if let anonUserId { dict["anon_user_id"] = anonUserId }
        if let conversationId { dict["loops_conversation_id"] = conversationId }
        return dict
    }

    public static var hostAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    public static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 { acc.append(Character(UnicodeScalar(UInt8(v)))) }
        }
        return id.isEmpty ? UIDevice.current.model : id
    }
}
