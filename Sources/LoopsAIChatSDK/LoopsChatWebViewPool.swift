import WebKit

/// A long-lived chat runtime: the `WKWebView` plus the bridge, session, analytics
/// and ready-state that belong to it. The engine — not the view controller — owns
/// everything durable, so the runtime (HTML/CSS/JS, the React tree, the SSE
/// connection, the conversation, the `ready` handshake) keeps running in the
/// background between presentations. Reopening just reattaches this WebView; it is
/// never torn down and re-fetched/re-parsed/re-bootstrapped while the app lives.
///
/// Persistent web→native messages (`ready`, `persistSession`, `trackEvent`) are
/// handled here even when no view controller is attached, so nothing is dropped
/// while the chat is closed. UI-facing callbacks are forwarded to `presenter` (the
/// currently-attached controller) and simply skipped when the chat is closed.
final class LoopsChatEngine {
    let webView: WKWebView
    let bridge: LoopsAIChatBridge
    /// Config the engine was built with — used for session ops + the one-time init
    /// handshake. (A reused engine keeps its original; the new presentation
    /// re-applies any per-open context via `updateContext`.)
    let config: LoopsAIChatConfig
    /// Natively-owned anon session (CONTRACT B.4). Outlives any single controller.
    let sessionStore: LoopsSessionStore
    /// Analytics fan-out. Lives on the engine so `trackEvent` dispatches even while
    /// the chat is closed (the host-facing delegate callback only fires when open).
    let analyticsDispatcher: LoopsAnalyticsDispatcher

    /// Mirrors the web `ready` handshake; persists so a warm reuse can fire
    /// `didBecomeReady` immediately without a reload.
    var isWebReady = false
    /// One-shot guard for the initial `initConfig` / `initContext` push.
    private var didSendInit = false
    /// The URL currently loaded — lets a reuse decide whether a reload is needed.
    var loadedURL: URL?

    /// The controller currently presenting this engine. **Weak** so it auto-clears
    /// when the controller is dismissed/deallocated — that, not a manual flag, is
    /// what makes the engine reliably available for the next open (UIKit teardown
    /// callbacks are unreliable for a SwiftUI representable's child controller).
    weak var presenter: LoopsAIChatViewController?

    /// Reusable when nothing is presenting it.
    var isAvailable: Bool { presenter == nil }

    init(
        webView: WKWebView,
        bridge: LoopsAIChatBridge,
        config: LoopsAIChatConfig,
        sessionStore: LoopsSessionStore,
        analyticsDispatcher: LoopsAnalyticsDispatcher
    ) {
        self.webView = webView
        self.bridge = bridge
        self.config = config
        self.sessionStore = sessionStore
        self.analyticsDispatcher = analyticsDispatcher
    }

    // MARK: - Persistent web → native handling (controller-independent)

    /// The web runtime finished mounting (`ready`). Push the one-time config/context
    /// and notify the presenter (if any) so it can reveal + fire `didBecomeReady`.
    func markReady() {
        isWebReady = true
        if !didSendInit {
            didSendInit = true
            bridge.sendInitConfig(to: webView, config: config)
            bridge.sendInitContext(to: webView, config: config)
        }
        presenter?.engineDidBecomeReady()
    }

    /// Re-dispatch a web `trackEvent` as a native canonical event and surface it to
    /// the host (only when a controller is attached). The dispatch itself always
    /// runs so analytics aren't lost while the chat is closed.
    func handleTrackEvent(_ payload: [String: Any]) {
        let context = LoopsAnalyticsContext(
            locale: config.locale,
            anonUserId: sessionStore.anonUserId,
            conversationId: sessionStore.conversationId(for: config.agentId)
        )
        guard let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context) else { return }
        analyticsDispatcher.dispatch(event)
        if let vc = presenter {
            vc.delegate?.loopsAIChat(vc, didEmitAnalyticsEvent: event)
        }
    }
}

/// Process-wide pool of long-lived chat engines (CONTRACT B — performance).
///
/// All engines use the persistent default `WKWebsiteDataStore`, so cookies /
/// localStorage / IndexedDB and the HTTP cache are shared and survive between
/// opens (and across the engine being reloaded). On top of that a small LRU of
/// engines is kept warm so the common case — the user closing the chat and
/// reopening it to the same agent — reuses the already-running runtime with no
/// network and no JS re-execution.
final class LoopsChatWebViewPool {
    static let shared = LoopsChatWebViewPool()
    private init() {}

    /// Keyed by agent + environment + locale. Small cap: a host app almost always
    /// loads a single agent, and each warm engine retains a live web process.
    private var warm: [String: LoopsChatEngine] = [:]
    private var lru: [String] = []
    private let maxWarm = 2

    /// A `WKWebViewConfiguration` wired to the persistent data store. The caller
    /// adds its own script-message handler to the returned controller before
    /// building the `WKWebView`.
    func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = WKUserContentController()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 15.4, *) {
            configuration.preferences.isElementFullscreenEnabled = false
        }
        return configuration
    }

    /// Borrow a warm engine for `key`, or `nil` if none is reusable. Only an engine
    /// that is **idle** (no live presenter) and **ready** (completed the `ready`
    /// handshake) is handed out, so a reuse can reveal instantly and we never adopt
    /// a half-loaded runtime. The caller sets `engine.presenter` immediately after.
    func borrowWarmEngine(forKey key: String) -> LoopsChatEngine? {
        guard let engine = warm[key], engine.isAvailable, engine.isWebReady else { return nil }
        touch(key)
        return engine
    }

    /// Register a freshly-created engine so a later presentation can reuse it.
    func store(_ engine: LoopsChatEngine, forKey key: String) {
        warm[key] = engine
        touch(key)
        evictIfNeeded()
    }

    /// Release a presented engine back to the warm pool. The engine is already
    /// stored by key; clearing the presenter makes it available for reuse.
    func release(_ engine: LoopsChatEngine) {
        engine.presenter = nil
    }

    /// Drop a warm engine and detach its bridge handler. Use on logout / memory
    /// pressure, or when a non-reusable engine is being discarded.
    func purge(key: String) {
        guard let engine = warm.removeValue(forKey: key) else { return }
        tearDown(engine)
        lru.removeAll { $0 == key }
    }

    /// Drop every warm engine. Exposed to hosts via `LoopsAIChat.clearWebCache()`.
    func purgeAll() {
        for engine in warm.values { tearDown(engine) }
        warm.removeAll()
        lru.removeAll()
    }

    private func tearDown(_ engine: LoopsChatEngine) {
        engine.webView.stopLoading()
        engine.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: LoopsAIChatBridge.handlerName)
        engine.webView.removeFromSuperview()
    }

    private func touch(_ key: String) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func evictIfNeeded() {
        // Never evict an engine that is currently on screen; walk oldest→newest.
        while warm.count > maxWarm {
            guard let victimKey = lru.first(where: { warm[$0]?.isAvailable == true }) else { break }
            purge(key: victimKey)
        }
    }
}
