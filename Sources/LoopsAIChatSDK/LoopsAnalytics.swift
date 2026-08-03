import Foundation

/// A transport for canonical analytics events — the event schema shared with the
/// web runtime. Each adapter relabels/delivers to one target; the dispatcher
/// never knows the target.
///
/// `Sendable`: adapters are held in `LoopsAIChatConfig` and may run their
/// delivery off the main thread, so conforming types must be safe to share.
public protocol LoopsAnalyticsAdapter: Sendable {
    var id: String { get }
    func send(_ event: LoopsAnalyticsEvent)
}

/// Fans a canonical event out to the always-on Loops sink plus an optional
/// per-agent customer adapter (mirrors the web dispatcher).
/// The sink is isolated: a customer adapter can never suppress it.
public final class LoopsAnalyticsDispatcher: Sendable {
    private let sink: (any LoopsAnalyticsAdapter)?
    private let customer: (any LoopsAnalyticsAdapter)?

    public init(sink: (any LoopsAnalyticsAdapter)?, customer: (any LoopsAnalyticsAdapter)?) {
        self.sink = sink
        self.customer = customer
    }

    /// Fan a canonical event out to the always-on Loops sink plus the optional
    /// customer adapter. Public so a host can emit its own native events (e.g. a
    /// commerce funnel) through the same pipeline the bridge uses.
    public func dispatch(_ event: LoopsAnalyticsEvent) {
        sink?.send(event)
        customer?.send(event)
    }
}

// MARK: - Built-in adapters

/// Always-on sink → our backend ingest (Firestore via a `functions` endpoint).
/// Carries the canonical event unrelabelled.
public struct LoopsSinkAdapter: LoopsAnalyticsAdapter {
    public let id = "loops-sink"
    let endpoint: URL

    public init(endpoint: URL) { self.endpoint = endpoint }

    public func send(_ event: LoopsAnalyticsEvent) {
        guard JSONSerialization.isValidJSONObject(event.payload),
              let body = try? JSONSerialization.data(withJSONObject: event.payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}

/// Generic POST of the canonical event to a customer webhook (Mode A, provider-
/// agnostic). For warehouses / CDPs that accept raw JSON.
public struct HttpWebhookAdapter: LoopsAnalyticsAdapter {
    public let id = "http-webhook"
    let endpoint: URL
    let headers: [String: String]

    public init(endpoint: URL, headers: [String: String] = [:]) {
        self.endpoint = endpoint
        self.headers = headers
    }

    public func send(_ event: LoopsAnalyticsEvent) {
        guard JSONSerialization.isValidJSONObject(event.payload),
              let body = try? JSONSerialization.data(withJSONObject: event.payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}

/// Closure-backed adapter — the decoupling point for on-device provider SDKs
/// (Firebase `Analytics.logEvent`, Mixpanel, Segment) **without the core SDK
/// depending on them**. The host wires its provider in the closure:
///
/// ```swift
/// .block(id: "firebase") { event in
///     Analytics.logEvent(event.event, parameters: event.payload as? [String: Any])
/// }
/// ```
public struct BlockAnalyticsAdapter: LoopsAnalyticsAdapter {
    public let id: String
    private let handler: @Sendable (LoopsAnalyticsEvent) -> Void

    public init(id: String, _ handler: @escaping @Sendable (LoopsAnalyticsEvent) -> Void) {
        self.id = id
        self.handler = handler
    }

    public func send(_ event: LoopsAnalyticsEvent) { handler(event) }
}

/// Per-agent analytics configuration: which always-on sink and which customer
/// adapter to fan out to (selection happens server-side; the SDK is told the
/// resolved choice here — no per-customer native code).
public struct LoopsAnalyticsConfig: Sendable {
    /// Always-on Loops sink endpoint (`nil` disables the sink — e.g. tests).
    public var loopsSinkEndpoint: URL?
    /// The customer destination, if any (webhook / provider via `.block`).
    public var customerAdapter: (any LoopsAnalyticsAdapter)?

    public init(loopsSinkEndpoint: URL? = nil, customerAdapter: (any LoopsAnalyticsAdapter)? = nil) {
        self.loopsSinkEndpoint = loopsSinkEndpoint
        self.customerAdapter = customerAdapter
    }

    public static let `default` = LoopsAnalyticsConfig()

    func makeDispatcher() -> LoopsAnalyticsDispatcher {
        let sink = loopsSinkEndpoint.map { LoopsSinkAdapter(endpoint: $0) }
        return LoopsAnalyticsDispatcher(sink: sink, customer: customerAdapter)
    }
}
