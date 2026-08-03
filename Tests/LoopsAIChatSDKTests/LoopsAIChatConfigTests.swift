import XCTest
@testable import LoopsAIChatSDK

final class LoopsAIChatConfigTests: XCTestCase {
    func testDefaultBaseURL() {
        let config = LoopsAIChatConfig(agentId: "agent_test")
        XCTAssertEqual(config.baseURL.absoluteString, "https://chat.loopsai.com")
    }

    func testChatURLContainsModeAndPlatform() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let url = config.chatURL(anonUserId: nil, conversationId: nil)
        XCTAssertTrue(url.absoluteString.contains("mode=sdk"))
        XCTAssertTrue(url.absoluteString.contains("platform=ios"))
        XCTAssertTrue(url.absoluteString.contains("agent_123"))
    }

    func testChatURLIncludesLocale() {
        let config = LoopsAIChatConfig(agentId: "agent_123", locale: "tr")
        let url = config.chatURL(anonUserId: nil, conversationId: nil)
        XCTAssertTrue(url.absoluteString.contains("locale=tr"))
    }

    func testChatURLExcludesLocaleWhenNil() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let url = config.chatURL(anonUserId: nil, conversationId: nil)
        XCTAssertFalse(url.absoluteString.contains("locale="))
    }

    func testChatURLNormalizesRegionalLocale() {
        for raw in ["tr_TR", "tr-TR", "TR", " tr "] {
            let config = LoopsAIChatConfig(agentId: "agent_123", locale: raw)
            let url = config.chatURL(anonUserId: nil, conversationId: nil)
            XCTAssertTrue(
                url.absoluteString.contains("locale=tr"),
                "expected locale=tr for \(raw)"
            )
            XCTAssertFalse(url.absoluteString.lowercased().contains("tr_tr"))
            XCTAssertFalse(url.absoluteString.lowercased().contains("tr-tr"))
        }
    }

    func testChatURLExcludesLocaleWhenBlank() {
        let config = LoopsAIChatConfig(agentId: "agent_123", locale: "   ")
        let url = config.chatURL(anonUserId: nil, conversationId: nil)
        XCTAssertFalse(url.absoluteString.contains("locale="))
    }

    func testWebCacheKeyIgnoresLocaleSpelling() {
        let regional = LoopsAIChatConfig(agentId: "agent_123", locale: "tr-TR")
        let base = LoopsAIChatConfig(agentId: "agent_123", locale: "tr")
        XCTAssertEqual(regional.webCacheKey, base.webCacheKey)
    }

    func testChatURLInjectsSessionParams() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let url = config.chatURL(anonUserId: "anon_42", conversationId: "cnv_7")
        XCTAssertTrue(url.absoluteString.contains("_lsuid=anon_42"))
        XCTAssertTrue(url.absoluteString.contains("_lscid=cnv_7"))
    }

    func testChatURLOmitsSessionParamsWhenNil() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let url = config.chatURL(anonUserId: nil, conversationId: nil)
        XCTAssertFalse(url.absoluteString.contains("_lsuid="))
        XCTAssertFalse(url.absoluteString.contains("_lscid="))
    }

    func testChatURLFreshOmitsConversationAndAddsFreshFlag() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let url = config.chatURL(anonUserId: "anon_42", conversationId: "cnv_7", fresh: true)
        // Fresh starts a new conversation: no _lscid, fresh=true, but keep the user.
        XCTAssertTrue(url.absoluteString.contains("fresh=true"))
        XCTAssertFalse(url.absoluteString.contains("_lscid="))
        XCTAssertTrue(url.absoluteString.contains("_lsuid=anon_42"))
    }

    func testStartFreshConfigDefaultsFalse() {
        XCTAssertFalse(LoopsAIChatConfig(agentId: "agent_123").startFresh)
        XCTAssertTrue(LoopsAIChatConfig(agentId: "agent_123", startFresh: true).startFresh)
    }

    func testCustomEnvironmentHost() {
        let config = LoopsAIChatConfig(
            agentId: "agent_123",
            environment: .custom(URL(string: "https://chat.acme.com")!)
        )
        XCTAssertEqual(config.baseHost, "chat.acme.com")
    }

    func testContextPayloadConstruction() {
        let context = LoopsAIChatContext(
            productContext: ["productCode": "SKU123", "productName": "T-Shirt"],
            userContext: ["userId": "u_42", "email": "john@example.com"]
        )
        let payload = context.toPayload()
        XCTAssertNotNil(payload["productContext"])
        XCTAssertNotNil(payload["userContext"])
    }

    func testContextPayloadOmitsNilFields() {
        let context = LoopsAIChatContext(
            productContext: ["productCode": "SKU123"]
        )
        let payload = context.toPayload()
        XCTAssertNotNil(payload["productContext"])
        XCTAssertNil(payload["userContext"])
    }

    func testEmptyContextPayload() {
        let context = LoopsAIChatContext()
        let payload = context.toPayload()
        XCTAssertTrue(payload.isEmpty)
    }
}
