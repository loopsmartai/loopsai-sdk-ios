import UIKit
import WebKit
import SafariServices

open class LoopsAIChatViewController: UIViewController {
    public let config: LoopsAIChatConfig

    /// Natively-owned anonymous session. Exposed so a host can
    /// share one store across multiple chat presentations if desired.
    public let sessionStore: LoopsSessionStore

    public weak var delegate: LoopsAIChatDelegate?

    /// The presented runtime (WKWebView + bridge + ready state). Borrowed warm
    /// from `LoopsChatWebViewPool` when keep-alive is on, otherwise created cold.
    private var engine: LoopsChatEngine!
    /// True when `engine` was reused warm (already loaded) — skip the cold load.
    private var reusedWarmEngine = false
    private lazy var analyticsDispatcher = config.analytics.makeDispatcher()

    internal var webView: WKWebView? { engine?.webView }
    private var bridge: LoopsAIChatBridge { engine.bridge }
    private var isWebReady: Bool {
        get { engine?.isWebReady ?? false }
        set { engine?.isWebReady = newValue }
    }
    /// One-shot: when set, the next load starts a fresh conversation (skips
    /// `_lscid`, passes `fresh=true`). Seeded from `config.startFresh`.
    private lazy var startFreshOnNextLoad: Bool = config.startFresh
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var errorView: UIView?
    private var closeButton: UIButton?

    public init(
        config: LoopsAIChatConfig,
        delegate: LoopsAIChatDelegate? = nil,
        sessionStore: LoopsSessionStore = LoopsSessionStore()
    ) {
        self.config = config
        self.sessionStore = sessionStore
        super.init(nibName: nil, bundle: nil)
        self.delegate = delegate
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupActivityIndicator()
        if config.showCloseButton {
            setupCloseButton()
        }

        if reusedWarmEngine && !config.startFresh {
            // Warm path: the runtime is already loaded + ready — reattach with no
            // network, no reload, no JS re-execution. Instant reopen.
            resumeWarmEngine()
        } else {
            if reusedWarmEngine {
                // Reused the WebView but the host asked for a fresh conversation:
                // reload in place (warm process + cached assets → still fast).
                isWebReady = false
            }
            bootstrapSessionThenLoad()
        }
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    /// On rotation / size-class change, tell the web runtime whether the layout is
    /// compact (`mobileStateChange`). Uses the horizontal size class —
    /// the correct iOS signal — rather than a raw width threshold (an iPhone in
    /// landscape is still a compact, "mobile" layout). The initial state is seeded
    /// in the load URL; this keeps the runtime in sync afterwards.
    open override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            self.sendMobileStateChange(isMobile: self.traitCollection.horizontalSizeClass == .compact)
        }
    }

    private func setupWebView() {
        let key = config.webCacheKey

        // Reuse a warm, ready engine when keep-alive is on and one is free.
        if config.keepAliveEnabled,
           let warm = LoopsChatWebViewPool.shared.borrowWarmEngine(forKey: key) {
            engine = warm
            reusedWarmEngine = true
        } else {
            engine = makeEngine()
            if config.keepAliveEnabled {
                LoopsChatWebViewPool.shared.store(engine, forKey: key)
            }
        }

        let wv = engine.webView
        // (Re)point the bridge + web delegates at THIS controller. A warm engine
        // still references the previously-presented (now-dismissed) controller, so
        // this re-wiring must happen on every presentation, warm or cold.
        if let host = config.baseHost { bridge.allowedHosts.insert(host) }
        engine.presenter = self
        wv.navigationDelegate = self
        wv.uiDelegate = self

        // A warm WebView may still be parented in the dismissed controller's view.
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wv)

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    /// Build a cold engine: a fresh bridge + a `WKWebView` on the persistent data
    /// store, so the HTTP cache / cookies / localStorage are shared and survive
    /// across opens even when keep-alive is disabled.
    private func makeEngine() -> LoopsChatEngine {
        let newBridge = LoopsAIChatBridge()
        let configuration = LoopsChatWebViewPool.shared.makeConfiguration()
        configuration.userContentController.add(newBridge, name: LoopsAIChatBridge.handlerName)

        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces = false
        wv.isOpaque = false
        wv.backgroundColor = .systemBackground
        wv.alpha = 0

        if #available(iOS 16.4, *) {
            #if DEBUG
            wv.isInspectable = true
            #else
            wv.isInspectable = false
            #endif
        }

        let engine = LoopsChatEngine(
            webView: wv,
            bridge: newBridge,
            config: config,
            sessionStore: sessionStore,
            analyticsDispatcher: analyticsDispatcher
        )
        newBridge.engine = engine
        return engine
    }

    /// Reattach a still-loaded, already-ready runtime. No network, no reload — show
    /// it immediately and re-fire readiness so the host re-applies context and runs
    /// its entry-point intent (suggestSize / VTO / search) on the warm WebView.
    private func resumeWarmEngine() {
        activityIndicator.stopAnimating()
        webView?.alpha = 1
        closeButton?.alpha = 1
        // borrowWarmEngine only hands out ready engines, so `isWebReady` is true.
        engineDidBecomeReady()
    }


    private func setupActivityIndicator() {
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.accessibilityLabel = "Loading chat"
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        activityIndicator.startAnimating()
    }

    private func setupCloseButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let xImage = UIImage(systemName: "xmark", withConfiguration: symbolConfig)
        button.setImage(xImage, for: .normal)
        button.tintColor = .secondaryLabel

        button.backgroundColor = UIColor.secondarySystemBackground
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true

        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        button.alpha = 0
        button.accessibilityLabel = "Close"
        button.accessibilityHint = "Closes the chat"

        view.addSubview(button)
        closeButton = button

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    @objc private func closeButtonTapped() {
        delegate?.loopsAIChatDidRequestClose(self)
    }

    // MARK: - Session + load

    /// Resolves the anon session natively, then loads the runtime
    /// with `_lsuid` / `_lscid` injected. Falls back to the cached session (or
    /// none) if bootstrap fails — the web runtime can still self-bootstrap.
    private func bootstrapSessionThenLoad() {
        let bootstrapper = LoopsSessionBootstrapper(baseURL: config.baseURL, store: sessionStore)
        bootstrapper.bootstrap(agentId: config.agentId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failure(let error) = result {
                    self.delegate?.loopsAIChat(self, didFailWith: error)
                }
                self.loadChat()
            }
        }
    }

    private func loadChat() {
        removeErrorView()
        activityIndicator.startAnimating()
        // `startFreshOnNextLoad` is one-shot: consume it so a later reload (e.g.
        // retry) resumes normally once the new conversation has been persisted.
        let fresh = startFreshOnNextLoad
        startFreshOnNextLoad = false
        let url = config.chatURL(
            anonUserId: sessionStore.anonUserId,
            conversationId: fresh ? nil : sessionStore.conversationId(for: config.agentId),
            fresh: fresh
        )
        engine?.loadedURL = url
        webView?.load(URLRequest(url: url))
    }

    // MARK: - Public API (native → web)

    public func updateContext(_ context: LoopsAIChatContext) {
        guard let webView, isWebReady else { return }
        bridge.sendUpdateContext(to: webView, context: context)
    }

    public func sendMessage(_ message: String) {
        guard let webView, isWebReady else { return }
        bridge.send(.sendUserMessage, payload: ["message": message], to: webView)
    }

    public func startVirtualTryOn(product: [String: String]) {
        guard let webView, isWebReady else { return }
        bridge.send(.startVirtualTryOn, payload: ["product": product], to: webView)
    }

    /// Try on the product currently quoted in the conversation.
    public func startTryOnFromQuote() {
        guard let webView, isWebReady else { return }
        bridge.send(.startTryOnFromQuote, to: webView)
    }

    /// Quote a specific product in the conversation (`quoteProduct`):
    /// the runtime shows that product as a card **above the input** — the same
    /// "quoted product" UI the chat uses when referencing a product — so the user
    /// can ask their own question about it. No message is sent; the user types it.
    ///
    /// This is the native equivalent of the web embed's `quoteProduct(...)` and the
    /// "Ask about this product" entry point. Pairs with `clearProductQuote()` (drop
    /// the quote) and `startTryOnFromQuote()` (try on the quoted product).
    /// - Parameter product: product context; **must include `productCode`** (or
    ///   `code`). The runtime resolves the full product by code and renders the card.
    public func quoteProduct(product: [String: String]) {
        guard let webView, isWebReady else { return }
        bridge.send(.quoteProduct, payload: ["product": product], to: webView)
    }

    public func suggestSize() {
        guard let webView, isWebReady else { return }
        bridge.send(.suggestSize, to: webView)
    }

    /// Open the chat in AI search mode with a prefilled query
    /// (`searchEscalation`). Defaults to a **product search** — matching the web
    /// embed's `openWithSearch`, which sends `isOnlySearchProducts: true` so the
    /// runtime returns product results rather than treating the query as an
    /// ordinary chat message. Pass `productsOnly: false` to escalate into a
    /// conversational answer instead.
    /// - Parameter productsOnly: `true` (default) for AI product search; `false`
    ///   to escalate the query into the conversation.
    public func openWithSearch(_ query: String, productsOnly: Bool = true) {
        guard let webView, isWebReady else { return }
        bridge.send(
            .searchEscalation,
            payload: ["query": query, "isOnlySearchProducts": productsOnly],
            to: webView
        )
    }

    /// Sync a known customer into the conversation
    /// (`syncCustomerDetails`). The web runtime looks up the profile for
    /// `customerId` and enriches the session. Use when your app already knows who
    /// the user is (e.g. after login) so chat / size / recs are personalized.
    public func syncCustomerDetails(customerId: String) {
        guard let webView, isWebReady else { return }
        bridge.send(.syncCustomerDetails, payload: ["customerId": customerId], to: webView)
    }

    /// Match the chat typography to your app (`setWebsiteFont`).
    /// - Parameter fontFamily: a CSS `font-family` value the web runtime applies.
    public func setWebsiteFont(_ fontFamily: String) {
        guard let webView, isWebReady else { return }
        bridge.send(.setWebsiteFont, payload: ["fontFamily": fontFamily], to: webView)
    }

    /// Start a brand-new conversation, discarding the resume pointer. Reloads the
    /// runtime with `fresh=true` so no prior conversation — neither the locally
    /// cached one nor the server's most-recent — is restored. The fresh
    /// conversation is persisted back natively once the web runtime reports it
    /// (`persistSession`), so a later relaunch resumes *it*.
    public func startNewConversation() {
        sessionStore.setConversationId(nil, for: config.agentId)
        startFreshOnNextLoad = true
        isWebReady = false
        loadChat()
    }

    /// Set the analytics consent state from your app's consent management platform
    /// (`setAnalyticsConsent`). The web runtime maps this to its own
    /// consent gate: `granted` lets analytics dispatch, `false` denies it (stops
    /// every adapter, including the always-on Loops sink). Call this whenever the
    /// user updates their consent; it is forward-compatible (older web runtimes
    /// simply ignore the action).
    /// - Parameter granted: `true` to grant analytics consent, `false` to deny it.
    public func setAnalyticsConsent(_ granted: Bool) {
        guard let webView, isWebReady else { return }
        bridge.send(.setAnalyticsConsent, payload: ["granted": granted], to: webView)
    }

    /// Clear the active product quote in the conversation
    /// (`clearProductQuote`). Pairs with the `didChangeProductQuote` delegate
    /// callback: when your app dismisses its native quote chip, call this so the
    /// web runtime drops the quote too.
    public func clearProductQuote() {
        guard let webView, isWebReady else { return }
        bridge.send(.clearProductQuote, to: webView)
    }

    /// Close any open web overlay — virtual try-on, size input, sidebars, drawers —
    /// without unloading the WebView (`closeOverlays`). Wire this to a
    /// back gesture / dismiss button so a system back closes the overlay first
    /// instead of tearing down the chat.
    public func closeOverlays() {
        guard let webView, isWebReady else { return }
        bridge.send(.closeOverlays, to: webView)
    }

    /// Tell the web runtime the mobile/compact layout state changed
    /// (`mobileStateChange`). Called automatically on rotation / size-class change;
    /// the initial state is still seeded via the load URL.
    private func sendMobileStateChange(isMobile: Bool) {
        guard let webView, isWebReady else { return }
        bridge.send(.mobileStateChange, payload: ["isMobile": isMobile], to: webView)
    }

    // MARK: - Engine callbacks (web → native)

    /// The engine reached `ready` (it already pushed config/context). Reveal the
    /// WebView and notify the host. `ready`/`persistSession`/`trackEvent` are now
    /// owned by the engine so they survive while the chat is closed.
    func engineDidBecomeReady() {
        activityIndicator.stopAnimating()
        UIView.animate(withDuration: 0.2) {
            self.webView?.alpha = 1
            self.closeButton?.alpha = 1
        }
        delegate?.loopsAIChatDidBecomeReady(self)
    }

    /// The web runtime asked the host to refresh an auth token.
    /// v1 launches are anon-only; with no `authProvider` this is a no-op.
    func handleTokenRefreshRequest(requestId: String?) {
        // Reserved for the optional auth provider.
    }

    // MARK: - Outbound links

    /// Single entry point for links that must leave the chat WebView: foreign-host
    /// navigations, `_blank` / `window.open` requests, and the `openExternalUrl`
    /// bridge action. Routes to the host so a custom `didRequestOpenURL` can take
    /// over native routing; otherwise the delegate default presents the in-app
    /// browser. The URL is forwarded verbatim so the query (e.g. `loops_ref`
    /// Custom Attribution) survives.
    func handleOutboundURL(_ url: URL) {
        delegate?.loopsAIChat(self, didRequestOpenURL: url)
    }

    /// SDK default for outbound links: open in an in-app `SFSafariViewController`
    /// from the top-most presented controller, preserving the exact URL. Non-web
    /// schemes (mailto/tel/custom) fall back to the system opener since
    /// `SFSafariViewController` only supports http/https.
    public func presentInAppBrowser(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            UIApplication.shared.open(url)
            return
        }
        var presenter: UIViewController = self
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(SFSafariViewController(url: url), animated: true)
    }

    // MARK: - Error UI

    private func showErrorView() {
        guard errorView == nil else { return }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Unable to load chat"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15, weight: .medium)

        let button = UIButton(type: .system)
        button.setTitle("Retry", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        errorView = container
    }

    private func removeErrorView() {
        errorView?.removeFromSuperview()
        errorView = nil
    }

    @objc private func retryTapped() {
        loadChat()
    }

    /// A SwiftUI `UIViewControllerRepresentable` tears its controller down by
    /// removing it from its parent (not by "dismissing" it), so `viewDidDisappear`'s
    /// `isBeingDismissed`/`isMovingFromParent` can both be false. Releasing here on
    /// parent removal guarantees the engine becomes reusable for the next open.
    open override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if parent == nil { teardownEngine() }
    }

    /// When this controller is actually leaving the screen (dismissed or popped —
    /// not merely covered), hand the engine back. With keep-alive on, the runtime
    /// is kept warm in the pool for an instant reopen; otherwise it is disposed.
    /// (The weak `presenter` also auto-clears on dealloc, so reuse never gets stuck
    /// even if neither this nor `willMove` fires.)
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        teardownEngine()
    }

    private func teardownEngine() {
        guard let engine else { return }
        // If a newer presentation already adopted this engine, leave it untouched —
        // detaching its WebView or clearing its presenter would break that one.
        // (Idempotent: a second call after `self.engine = nil` is a no-op.)
        guard engine.presenter == nil || engine.presenter === self else {
            self.engine = nil
            return
        }

        if config.keepAliveEnabled {
            // Keep the runtime warm: detach the view + release the presenter slot so
            // the engine is reusable. The script handler stays registered (pool owns it).
            engine.webView.removeFromSuperview()
            LoopsChatWebViewPool.shared.release(engine)
        } else {
            // Cold mode: this controller solely owns the engine — fully dispose it.
            engine.webView.stopLoading()
            engine.webView.configuration.userContentController
                .removeScriptMessageHandler(forName: LoopsAIChatBridge.handlerName)
            engine.webView.removeFromSuperview()
        }
        self.engine = nil
    }

    deinit {
        // Safety net for a cold engine that teardown didn't reach (e.g. dealloc
        // without viewDidDisappear). Warm engines are owned by the pool — leave them.
        if let engine, !config.keepAliveEnabled {
            engine.webView.configuration.userContentController
                .removeScriptMessageHandler(forName: LoopsAIChatBridge.handlerName)
        }
    }
}

extension LoopsAIChatViewController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if let host = url.host, bridge.allowedHosts.contains(host) {
            decisionHandler(.allow)
            return
        }

        // Foreign link → open outside the WebView.
        handleOutboundURL(url)
        decisionHandler(.cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Visual readiness only — the bridge-level `ready` action drives init.
        activityIndicator.stopAnimating()
        UIView.animate(withDuration: 0.25) {
            webView.alpha = 1
            self.closeButton?.alpha = 1
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        showErrorView()
        delegate?.loopsAIChat(self, didFailWith: .load(underlying: error.localizedDescription))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        showErrorView()
        delegate?.loopsAIChat(self, didFailWith: .load(underlying: error.localizedDescription))
    }

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}

extension LoopsAIChatViewController: WKUIDelegate {
    /// `target="_blank"` / `window.open` navigations never reach `decidePolicyFor`,
    /// so intercept the new-window request here and route it through the same
    /// outbound path, returning nil so no popup WebView is created.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            handleOutboundURL(url)
        }
        return nil
    }

    /// Grant media capture only to allowlisted origins. The host app still needs the
    /// matching usage-description key in its Info.plist or iOS denies the prompt.
    @available(iOS 15.0, *)
    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let allowed = bridge.allowedHosts.contains(origin.host)
        decisionHandler(allowed ? .grant : .deny)
    }
}
