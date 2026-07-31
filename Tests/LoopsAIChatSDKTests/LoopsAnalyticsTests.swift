import XCTest
@testable import LoopsAIChatSDK

/// Native analytics bridge tests (canonical event schema).
final class LoopsAnalyticsTests: XCTestCase {

    private func context() -> LoopsAnalyticsContext {
        LoopsAnalyticsContext(
            appVersion: "1.2.3",
            device: "iPhone16,1",
            osVersion: "18.0",
            locale: "tr",
            anonUserId: "anon_1",
            conversationId: "cnv_1"
        )
    }

    func testEventForcesIOSChannelAndSchema() {
        let payload: [String: Any] = ["event": ["event": "loops_ai_view_item_list", "channel": "web"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.event, "loops_ai_view_item_list")
        XCTAssertEqual(event?.channel, "ios")
        XCTAssertEqual(event?.payload["channel"] as? String, "ios")
        XCTAssertEqual(event?.payload["schema_version"] as? String, "1.0")
    }

    func testEventAttachesNativeContext() {
        let payload: [String: Any] = ["event": ["event": "loops_ai_select_item"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.payload["app_version"] as? String, "1.2.3")
        XCTAssertEqual(event?.payload["device"] as? String, "iPhone16,1")
        XCTAssertEqual(event?.payload["os_version"] as? String, "18.0")
        XCTAssertEqual(event?.payload["anon_user_id"] as? String, "anon_1")
        XCTAssertEqual(event?.payload["loops_conversation_id"] as? String, "cnv_1")
    }

    func testEventToleratesBareEnvelope() {
        // Web may send the canonical event at the top level instead of nested.
        let payload: [String: Any] = ["event": "loops_ai_select_item", "loops_agent_id": "agt_9"]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.event, "loops_ai_select_item")
        XCTAssertEqual(event?.payload["loops_agent_id"] as? String, "agt_9")
    }

    func testEventRejectsMissingName() {
        let payload: [String: Any] = ["event": ["channel": "web"]]
        XCTAssertNil(LoopsAnalyticsEvent(bridgePayload: payload, context: context()))
    }

    func testWebContextDoesNotOverrideNativeChannel() {
        // Even if web claims a different channel, native wins.
        let payload: [String: Any] = ["event": ["event": "loops_ai_view_item_list", "channel": "whatsapp"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.payload["channel"] as? String, "ios")
    }

    func testKindReadsInteractionFromPayloadLevel() {
        let payload: [String: Any] = ["kind": "interaction", "event": ["event": "loops_ai_message_sent"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.kind, "interaction")
        XCTAssertEqual(event?.payload["kind"] as? String, "interaction")
    }

    func testKindReadsInteractionFromEventEnvelope() {
        let payload: [String: Any] = ["event": ["event": "loops_ai_message_sent", "kind": "interaction"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.kind, "interaction")
        XCTAssertEqual(event?.payload["kind"] as? String, "interaction")
    }

    func testKindDefaultsToEcommerceWhenAbsent() {
        let payload: [String: Any] = ["event": ["event": "loops_ai_view_item_list"]]
        let event = LoopsAnalyticsEvent(bridgePayload: payload, context: context())
        XCTAssertEqual(event?.kind, "ecommerce")
    }

    // MARK: - Dispatcher

    func testDispatcherFansOutToSinkAndCustomer() {
        let sinkRec = EventRecorder()
        let customerRec = EventRecorder()
        let sink = BlockAnalyticsAdapter(id: "sink") { sinkRec.record($0.event) }
        let customer = BlockAnalyticsAdapter(id: "customer") { customerRec.record($0.event) }
        let dispatcher = LoopsAnalyticsDispatcher(sink: sink, customer: customer)

        let event = LoopsAnalyticsEvent(
            bridgePayload: ["event": ["event": "loops_ai_select_item"]],
            context: context()
        )!
        dispatcher.dispatch(event)

        XCTAssertEqual(sinkRec.all, ["loops_ai_select_item"])
        XCTAssertEqual(customerRec.all, ["loops_ai_select_item"])
    }

    func testDispatcherWithoutCustomerStillHitsSink() {
        let sinkRec = EventRecorder()
        let sink = BlockAnalyticsAdapter(id: "sink") { sinkRec.record($0.event) }
        let dispatcher = LoopsAnalyticsDispatcher(sink: sink, customer: nil)
        let event = LoopsAnalyticsEvent(
            bridgePayload: ["event": ["event": "loops_ai_select_item"]],
            context: context()
        )!
        dispatcher.dispatch(event)
        XCTAssertEqual(sinkRec.count, 1)
    }

    func testConfigBuildsSinkAdapterFromEndpoint() {
        let config = LoopsAnalyticsConfig(
            loopsSinkEndpoint: URL(string: "https://ingest.loopsai.com/e")!
        )
        // Dispatcher is built without throwing; sink present, no customer.
        let dispatcher = config.makeDispatcher()
        XCTAssertNotNil(dispatcher)
    }
}
