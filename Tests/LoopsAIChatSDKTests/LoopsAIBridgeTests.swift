import XCTest
import WebKit
@testable import LoopsAIChatSDK

/// Bridge-contract tests (native channel typed envelope).
final class LoopsAIBridgeTests: XCTestCase {

    // MARK: - Inbound envelope parsing

    func testParsesValidNativeActionEnvelope() {
        let body: [String: Any] = [
            "protocolVersion": 1,
            "type": "nativeAction",
            "name": "productQuoteChanged",
            "requestId": "req_123",
            "payload": ["product": ["code": "SKU1"]]
        ]
        let msg = LoopsAIInboundMessage(body: body)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.name, "productQuoteChanged")
        XCTAssertEqual(msg?.requestId, "req_123")
        XCTAssertEqual(msg?.protocolVersion, 1)
        XCTAssertNotNil(msg?.payload["product"])
    }

    func testRejectsNonNativeActionType() {
        let body: [String: Any] = ["type": "somethingElse", "name": "closeChat"]
        XCTAssertNil(LoopsAIInboundMessage(body: body))
    }

    func testRejectsMissingName() {
        let body: [String: Any] = ["type": "nativeAction", "payload": [:]]
        XCTAssertNil(LoopsAIInboundMessage(body: body))
    }

    func testRejectsLegacyFlatShape() {
        // The native channel ignores the iframe/embed flat `{action}` shape.
        let body: [String: Any] = ["action": "closeChat", "url": "https://x.com"]
        XCTAssertNil(LoopsAIInboundMessage(body: body))
    }

    func testDefaultsProtocolVersionWhenOmitted() {
        let body: [String: Any] = ["type": "nativeAction", "name": "ready"]
        let msg = LoopsAIInboundMessage(body: body)
        XCTAssertEqual(msg?.protocolVersion, LoopsAIBridgeProtocol.version)
        XCTAssertEqual(msg?.payload.isEmpty, true)
    }

    // MARK: - Allowlists (frozen for v1)

    func testWebActionAllowlistMatchesContract() {
        let expected: Set<String> = [
            "ready", "closeChat", "openProduct", "openModule", "openExternalUrl",
            "requestTokenRefresh", "trackEvent", "respondingStateChange",
            "productQuoteChanged", "conversationActive", "newChatStarted",
            "persistSession", "overlayOpen", "overlayClosed"
        ]
        let actual = Set(LoopsAIBridgeProtocol.WebAction.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected)
    }

    func testUnknownWebActionIsNotConstructible() {
        XCTAssertNil(LoopsAIBridgeProtocol.WebAction(rawValue: "deleteEverything"))
    }

    func testNativeActionRawValuesMatchContract() {
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.initConfig.rawValue, "initConfig")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.sendUserMessage.rawValue, "sendUserMessage")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.searchEscalation.rawValue, "searchEscalation")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.startTryOnFromQuote.rawValue, "startTryOnFromQuote")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.quoteProduct.rawValue, "quoteProduct")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.startVoiceMode.rawValue, "startVoiceMode")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.syncCustomerDetails.rawValue, "syncCustomerDetails")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.setWebsiteFont.rawValue, "setWebsiteFont")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.setAnalyticsConsent.rawValue, "setAnalyticsConsent")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.clearProductQuote.rawValue, "clearProductQuote")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.closeOverlays.rawValue, "closeOverlays")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.mobileStateChange.rawValue, "mobileStateChange")
        XCTAssertEqual(LoopsAIBridgeProtocol.NativeAction.widgetVisibility.rawValue, "widgetVisibility")
    }

    // MARK: - Feature flags

    func testFeatureFlagsDefaultEmptyPayload() {
        XCTAssertTrue(LoopsFeatureFlags.default.payload().isEmpty)
    }

    func testFeatureFlagsPayloadOnlyIncludesSetFlags() {
        let flags = LoopsFeatureFlags(virtualTryOnEnabled: false, searchEscalationEnabled: true)
        let payload = flags.payload()
        XCTAssertEqual(payload["searchEscalationEnabled"] as? Bool, true)
        XCTAssertEqual(payload["virtualTryOnEnabled"] as? Bool, false)
        XCTAssertNil(payload["productSuggestionEnabled"])
        XCTAssertNil(payload["outfitSuggestionEnabled"])
        XCTAssertEqual(payload.count, 2)
    }

    func testProtocolVersionIsOne() {
        XCTAssertEqual(LoopsAIBridgeProtocol.version, 1)
        XCTAssertEqual(LoopsAIBridgeProtocol.messageType, "nativeAction")
    }

    @MainActor
    func testWarmPreloadDoesNotReportVisibilityUntilPresented() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let vc = fixture.controller

        XCTAssertEqual(fixture.webView.names, [])

        vc.openWithSearch("prepared search")
        XCTAssertEqual(fixture.webView.names, ["searchEscalation"])

        vc.viewDidAppear(false)
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": true])

        vc.engineDidBecomeReady()
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility"])

        vc.willMove(toParent: nil)
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility", "widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": false])

        vc.willMove(toParent: nil)
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility", "widgetVisibility"])
    }

    @MainActor
    func testReadyAfterAppearanceDeliversPendingThenVisibility() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let engine = fixture.engine
        let vc = fixture.controller

        engine.isWebReady = false
        vc.viewDidAppear(false)
        vc.openWithSearch("first")
        vc.openWithSearch("last")
        XCTAssertEqual(fixture.webView.names, [])

        engine.isWebReady = true
        vc.engineDidBecomeReady()
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility"])
        XCTAssertEqual(
            (fixture.webView.envelopes[0]["payload"] as? [String: Any])?["query"] as? String,
            "last"
        )
        XCTAssertEqual(fixture.webView.envelopes[1]["payload"] as? [String: Bool], ["visible": true])
    }

    @MainActor
    func testPreloadedControllerRemovedBeforeAppearanceSendsNoVisibility() {
        let fixture = makeWarmFixture()
        fixture.controller.willMove(toParent: nil)
        XCTAssertEqual(fixture.webView.names, [])
        fixture.cleanup()
    }

    @MainActor
    func testDismissingAncestorSuppressesReadyVisibility() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let parent = DismissingParentController()
        parent.addChild(fixture.controller)
        fixture.controller.didMove(toParent: parent)
        fixture.controller.viewDidAppear(false)
        fixture.controller.engineDidBecomeReady()
        XCTAssertEqual(fixture.webView.names, [])
    }

    @MainActor
    func testCoveredControllerReportsHiddenAndReopenedWithoutTeardown() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let vc = fixture.controller
        vc.viewDidAppear(false)
        vc.viewDidDisappear(false)
        XCTAssertEqual(fixture.webView.names, ["widgetVisibility", "widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": false])
        XCTAssertTrue(fixture.engine.presenter === vc)
        XCTAssertTrue(vc.webView === fixture.webView)
        vc.viewDidAppear(false)
        XCTAssertEqual(fixture.webView.names, ["widgetVisibility", "widgetVisibility", "widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": true])
        vc.viewDidAppear(false)
        XCTAssertEqual(fixture.webView.names.count, 3)
    }

    @MainActor
    func testPresentationInsideReadyCallbackKeepsSearchBeforeVisibility() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let delegate = PresentingReadyDelegate()
        fixture.controller.delegate = delegate
        fixture.controller.engineDidBecomeReady()
        XCTAssertEqual(fixture.webView.names, ["searchEscalation", "widgetVisibility"])
        XCTAssertEqual((fixture.webView.envelopes.first?["payload"] as? [String: Any])?["query"] as? String, "ready search")
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": true])
    }

    @MainActor
    func testReloadAfterVisibleReportsVisibilityToReplacementDocument() {
        let fixture = makeWarmFixture()
        defer { fixture.cleanup() }
        let vc = fixture.controller
        let engine = fixture.engine

        vc.viewDidAppear(false)
        XCTAssertEqual(fixture.webView.names, ["widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": true])

        engine.isWebReady = false
        fixture.webView.envelopes.removeAll()

        engine.markReady()
        XCTAssertEqual(fixture.webView.names, ["initConfig", "initContext", "widgetVisibility"])
        XCTAssertEqual(fixture.webView.envelopes.last?["payload"] as? [String: Bool], ["visible": true])

        engine.markReady()
        XCTAssertEqual(fixture.webView.names, ["initConfig", "initContext", "widgetVisibility"])
    }
}

@MainActor
private final class DismissingParentController: UIViewController {
    override var isBeingDismissed: Bool { true }
}

@MainActor
private final class PresentingReadyDelegate: LoopsAIChatDelegate {
    func loopsAIChatDidBecomeReady(_ viewController: LoopsAIChatViewController) {
        viewController.viewDidAppear(false)
        viewController.openWithSearch("ready search")
    }
}

@MainActor
private final class CapturingWebView: WKWebView {
    var envelopes: [[String: Any]] = []

    var names: [String] { envelopes.compactMap { $0["name"] as? String } }

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor (Any?, (any Error)?) -> Void)? = nil
    ) {
        if let start = javaScriptString.range(of: "window.postMessage("),
           let end = javaScriptString.range(of: ", '*');", options: .backwards),
           start.upperBound < end.lowerBound,
           let data = String(javaScriptString[start.upperBound..<end.lowerBound]).data(using: .utf8),
           let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            envelopes.append(envelope)
        }
        completionHandler?(nil, nil)
    }
}

@MainActor
private struct WarmFixture {
    let config: LoopsAIChatConfig
    let engine: LoopsChatEngine
    let controller: LoopsAIChatViewController
    let webView: CapturingWebView

    func cleanup() {
        controller.willMove(toParent: nil)
        LoopsChatWebViewPool.shared.purge(key: config.webCacheKey)
    }
}

@MainActor
private func makeWarmFixture() -> WarmFixture {
    let config = LoopsAIChatConfig(agentId: UUID().uuidString, showCloseButton: false)
    let webView = CapturingWebView(
        frame: .zero,
        configuration: LoopsChatWebViewPool.shared.makeConfiguration()
    )
    let bridge = LoopsAIChatBridge()
    let engine = LoopsChatEngine(
        webView: webView,
        bridge: bridge,
        config: config,
        sessionStore: LoopsSessionStore(),
        analyticsDispatcher: config.analytics.makeDispatcher()
    )
    bridge.engine = engine
    engine.isWebReady = true
    engine.loadedURL = config.chatURL(anonUserId: nil, conversationId: nil)
    LoopsChatWebViewPool.shared.store(engine, forKey: config.webCacheKey)
    let controller = LoopsAIChatViewController(config: config)
    controller.loadViewIfNeeded()
    return WarmFixture(config: config, engine: engine, controller: controller, webView: webView)
}
