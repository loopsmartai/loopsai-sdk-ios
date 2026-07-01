import XCTest
@testable import LoopsAIChatSDK

/// Production-hardening guarantees: strict concurrency + retry.
final class LoopsHardeningTests: XCTestCase {

    /// Compile-time proof that the config graph is `Sendable` (safe to pass
    /// across actors). If any stored property loses `Sendable`, this stops
    /// compiling — a regression fence, not a runtime assert.
    func testConfigGraphIsSendable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let config = LoopsAIChatConfig(
            agentId: "agt_x",
            environment: .production,
            features: LoopsFeatureFlags(virtualTryOnEnabled: true),
            analytics: LoopsAnalyticsConfig(
                loopsSinkEndpoint: URL(string: "https://ingest.loopsai.com/e")!,
                customerAdapter: BlockAnalyticsAdapter(id: "noop") { _ in }
            )
        )
        _ = requireSendable(config)
        _ = requireSendable(config.analytics)
        _ = requireSendable(config.features)
        _ = requireSendable(LoopsEnvironment.production)
    }

    func testSessionBootstrapRetriesThreeTimes() {
        XCTAssertEqual(LoopsSessionBootstrapper.maxAttempts, 3)
    }

    func testEnvironmentEquatable() {
        XCTAssertEqual(LoopsEnvironment.production, .production)
        let url = URL(string: "https://chat.acme.com")!
        XCTAssertEqual(LoopsEnvironment.custom(url), .custom(url))
        XCTAssertNotEqual(LoopsEnvironment.production, .custom(url))
    }

    func testBlockAdapterRunsHandler() {
        let rec = EventRecorder()
        let adapter = BlockAnalyticsAdapter(id: "x") { rec.record($0.event) }
        let event = LoopsAnalyticsEvent(
            bridgePayload: ["event": ["event": "loops_ai_select_item"]],
            context: LoopsAnalyticsContext(appVersion: "1", device: "d", osVersion: "18")
        )!
        adapter.send(event)
        XCTAssertEqual(rec.count, 1)
    }
}
