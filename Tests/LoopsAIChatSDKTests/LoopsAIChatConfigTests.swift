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
        XCTAssertTrue(url.absoluteString.contains("hostManagedVisibility=true"))
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

    func testWebCacheKeyDiffersOnPreviewToken() {
        let base = LoopsAIChatConfig(agentId: "agent_123")
        let preview = LoopsAIChatConfig(agentId: "agent_123", previewToken: "tok")
        XCTAssertNotEqual(base.webCacheKey, preview.webCacheKey)
    }

    func testWebCacheKeySeparatesHeaderSettings() {
        let base = LoopsAIChatConfig(agentId: "agent_123")
        let layout = LoopsHeaderLayout(left: [.history], right: [.favorites])
        XCTAssertNotEqual(base.webCacheKey, LoopsAIChatConfig(agentId: "agent_123", showCloseButton: false).webCacheKey)
        XCTAssertNotEqual(base.webCacheKey, LoopsAIChatConfig(agentId: "agent_123", closeButtonSlotWidth: 48).webCacheKey)
        XCTAssertNotEqual(base.webCacheKey, LoopsAIChatConfig(agentId: "agent_123", headerLayout: layout).webCacheKey)
    }

    func testCloseButtonSlotWidthRejectsInvalidValues() {
        XCTAssertEqual(LoopsAIChatConfig(agentId: "agent_123", closeButtonSlotWidth: -10).closeButtonSlotWidth, 0)
        XCTAssertEqual(LoopsAIChatConfig(agentId: "agent_123", closeButtonSlotWidth: .nan).closeButtonSlotWidth, 36)
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
    func testVersionPreviewURLPreservesIdentityAndEncodesToken() {
        let config = LoopsAIChatConfig(agentId: "agent_123", developmentMode: true, widgetVersion: " \nv7\t ", previewToken: " \ntoken+with/&=value\t ", agentVersion: " \nv3\t ")
        let url = config.chatURL(anonUserId: "anon_42", conversationId: "cnv_7")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["wv"], "v7")
        XCTAssertEqual(query["pt"], "token+with/&=value")
        XCTAssertEqual(query["av"], "v3")
        XCTAssertEqual(query["dev"], "1")
        XCTAssertEqual(query["_lsuid"], "anon_42")
        XCTAssertEqual(query["_lscid"], "cnv_7")
        XCTAssertEqual(query["platform"], "ios")
        XCTAssertTrue(url.absoluteString.contains("token%2Bwith"))
        XCTAssertFalse(URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedQuery!.contains("+"))
    }

    func testDefaultReleaseURLLeavesAssignmentToRuntime() {
        let config = LoopsAIChatConfig(agentId: "agent_123")
        let query = URLComponents(url: config.chatURL(anonUserId: "anon_42", conversationId: nil), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "_lsuid" }?.value, "anon_42")
        for key in ["wv", "pt", "av", "dev", "rv"] {
            XCTAssertFalse(query.contains { $0.name == key })
        }
    }

    func testBlankVersionsDoNotSendPreviewCredential() {
        let config = LoopsAIChatConfig(agentId: "agent_123", widgetVersion: " \n\t ", previewToken: "secret", agentVersion: " \n\t ")
        let names = URLComponents(url: config.chatURL(anonUserId: nil, conversationId: nil), resolvingAgainstBaseURL: false)!.queryItems!.map(\.name)
        for key in ["wv", "pt", "av"] { XCTAssertFalse(names.contains(key)) }
    }

    func testTestPointerDoesNotRequirePreviewCredential() {
        let config = LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "test")
        let query = URLComponents(url: config.chatURL(anonUserId: "anon_42", conversationId: "cnv_7", fresh: true), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "wv" }?.value, "test")
        XCTAssertEqual(query.first { $0.name == "_lsuid" }?.value, "anon_42")
        XCTAssertEqual(query.first { $0.name == "fresh" }?.value, "true")
        XCTAssertFalse(query.contains { $0.name == "pt" || $0.name == "_lscid" })
    }

    func testRuntimeCacheSeparatesVersionSelection() {
        let base = LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "v7", previewToken: "one", agentVersion: "v3")
        let variants = [
            LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "v8", previewToken: "one", agentVersion: "v3"),
            LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "v7", previewToken: "two", agentVersion: "v3"),
            LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "v7", agentVersion: "v3"),
            LoopsAIChatConfig(agentId: "agent_123", widgetVersion: "v7", previewToken: "one", agentVersion: "v4"),
            LoopsAIChatConfig(agentId: "agent_123", developmentMode: true, widgetVersion: "v7", previewToken: "one", agentVersion: "v3"),
            LoopsAIChatConfig(agentId: "agent_123")
        ]
        for config in variants { XCTAssertNotEqual(base.webCacheKey, config.webCacheKey) }
        let padded = LoopsAIChatConfig(agentId: "agent_123", widgetVersion: " \nv7 ", previewToken: " one\n", agentVersion: "\tv3\n")
        XCTAssertEqual(base.webCacheKey, padded.webCacheKey)
    }
}
