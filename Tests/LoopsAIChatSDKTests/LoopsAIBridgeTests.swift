import XCTest
@testable import LoopsAIChatSDK

/// Bridge-contract tests (CONTRACT Part B, native channel typed envelope).
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
        // The native channel ignores the iframe/embed flat `{action}` shape (B.1).
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
    }

    // MARK: - Feature flags (TASK-0016)

    func testFeatureFlagsDefaultEmptyPayload() {
        XCTAssertTrue(LoopsFeatureFlags.default.payload().isEmpty)
    }

    func testFeatureFlagsPayloadOnlyIncludesSetFlags() {
        let flags = LoopsFeatureFlags(searchEscalationEnabled: true, virtualTryOnEnabled: false)
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
}
