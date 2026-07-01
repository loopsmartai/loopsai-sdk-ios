import Foundation

/// Where the SDK loads the web runtime from (CONTRACT B.6 origin allowlist).
public enum LoopsEnvironment: Sendable, Equatable {
    case production            // chat.loopsai.com
    case custom(URL)           // self-host / on-prem (host added to the allowlist)

    var baseURL: URL {
        switch self {
        case .production: return URL(string: "https://chat.loopsai.com")!
        case .custom(let url): return url
        }
    }
}

public struct LoopsAIChatConfig: Sendable {
    public let agentId: String
    public let environment: LoopsEnvironment
    public let locale: String?
    public let initialContext: LoopsAIChatContext?
    public let showCloseButton: Bool
    public let features: LoopsFeatureFlags
    public let analytics: LoopsAnalyticsConfig

    /// Start a brand-new conversation instead of resuming the last one. When
    /// `true`, the first load skips `_lscid` and passes `fresh=true`, so the web
    /// runtime ignores any prior conversation (local + server). Use for entry
    /// points that should feel like a fresh start (e.g. an "Ask AI" search).
    public let startFresh: Bool

    /// Keep the chat's `WKWebView` warm across presentations so reopening is
    /// instant — the web runtime stays loaded in memory (no re-download, no JS
    /// re-execution, no re-bootstrap) and is reattached on the next open. The
    /// runtime also uses the persistent data store, so the HTTP cache / cookies /
    /// localStorage survive between opens regardless.
    /// Defaults to `true`. Set `false` to force a cold load each time (the warm
    /// engine is still bypassed) — e.g. for a kiosk that must reset per session.
    public let keepAliveEnabled: Bool

    /// Load the chat runtime even when the agent's web channel is inactive
    /// (staging / QA / design preview) — mirrors the web widget's `developmentMode`
    /// / `designMode`. Leave `false` in production so a disabled channel stays off.
    public let developmentMode: Bool
    public let designMode: Bool

    public init(
        agentId: String,
        environment: LoopsEnvironment = .production,
        initialContext: LoopsAIChatContext? = nil,
        features: LoopsFeatureFlags = .default,
        analytics: LoopsAnalyticsConfig = .default,
        locale: String? = nil,
        showCloseButton: Bool = true,
        startFresh: Bool = false,
        keepAliveEnabled: Bool = true,
        developmentMode: Bool = false,
        designMode: Bool = false
    ) {
        self.agentId = agentId
        self.environment = environment
        self.initialContext = initialContext
        self.features = features
        self.analytics = analytics
        self.locale = locale
        self.showCloseButton = showCloseButton
        self.startFresh = startFresh
        self.keepAliveEnabled = keepAliveEnabled
        self.developmentMode = developmentMode
        self.designMode = designMode
    }

    var baseURL: URL { environment.baseURL }

    /// Host the bridge must allow in addition to the canonical Loops hosts.
    var baseHost: String? { baseURL.host }

    /// Identity of the warm-engine bucket: same agent + origin + locale reuses the
    /// same kept-alive `WKWebView`. Different agents never share a runtime.
    var webCacheKey: String {
        "\(baseURL.absoluteString)|\(agentId)|\(locale ?? "")"
    }

    /// Builds the `mode=sdk` chat URL, re-injecting the natively-owned session
    /// (`_lsuid` / `_lscid`) on every load (CONTRACT B.4).
    ///
    /// When `fresh` is `true`, `_lscid` is omitted and `fresh=true` is added so
    /// the web runtime starts a new conversation and ignores any prior one
    /// (local cache + server's most-recent). The anon user (`_lsuid`) is kept so
    /// the new conversation still belongs to the same pseudonymous user.
    func chatURL(anonUserId: String?, conversationId: String?, fresh: Bool = false) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(agentId),
            resolvingAgainstBaseURL: false
        )!

        var queryItems = [
            URLQueryItem(name: "embedded", value: "true"),
            URLQueryItem(name: "mode", value: "sdk"),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "isMobile", value: "true")
        ]

        if let anonUserId { queryItems.append(URLQueryItem(name: "_lsuid", value: anonUserId)) }
        if fresh {
            queryItems.append(URLQueryItem(name: "fresh", value: "true"))
        } else if let conversationId {
            queryItems.append(URLQueryItem(name: "_lscid", value: conversationId))
        }
        if let locale { queryItems.append(URLQueryItem(name: "locale", value: locale)) }

        components.queryItems = queryItems
        return components.url!
    }
}
