import Foundation
import WebKit

/// Native side of the `mode=sdk` bridge.
///
/// Inbound: decodes the typed envelope, enforces the origin + name allowlist, and
/// routes to the host delegate / session owner. Outbound: wraps native→web actions
/// in the same typed envelope.
final class LoopsAIChatBridge: NSObject, WKScriptMessageHandler {
    /// Must match the web runtime's `window.webkit.messageHandlers.loopsAIBridge`.
    static let handlerName = "loopsAIBridge"

    /// The long-lived engine this bridge belongs to. Persistent actions (`ready`,
    /// `persistSession`, `trackEvent`) are handled on the engine so they survive
    /// while the chat is closed; UI actions route to `engine.presenter`.
    weak var engine: LoopsChatEngine?

    /// Hosts allowed to drive the bridge. The VC injects the custom `baseURL` host.
    var allowedHosts: Set<String> = [
        "chat.loopsai.com",
        "test-webchat.loopsai.com"
    ]

    // MARK: - Inbound (web → native)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName else { return }

        // Origin allowlist + main-frame only.
        if let host = message.frameInfo.request.url?.host,
           !allowedHosts.contains(host) {
            return
        }
        guard message.frameInfo.isMainFrame else { return }

        guard let inbound = LoopsAIInboundMessage(body: message.body) else { return }
        guard let action = LoopsAIBridgeProtocol.WebAction(rawValue: inbound.name) else {
            // Unknown name → ignored.
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.handle(action, message: inbound)
        }
    }

    private func handle(_ action: LoopsAIBridgeProtocol.WebAction, message: LoopsAIInboundMessage) {
        guard let engine else { return }
        let payload = message.payload

        // Persistent actions — handled on the engine even with no controller
        // attached, so nothing is lost while the chat is closed in the background.
        switch action {
        case .ready:
            engine.markReady()
            return
        case .persistSession:
            engine.sessionStore.apply(persistSession: payload)
            return
        case .trackEvent:
            engine.handleTrackEvent(payload)
            return
        default:
            break
        }

        // UI actions — require a live presenter; dropped when the chat is closed.
        guard let vc = engine.presenter else { return }
        let delegate = vc.delegate

        switch action {
        case .closeChat:
            delegate?.loopsAIChatDidRequestClose(vc)

        case .openProduct, .openModule:
            delegate?.loopsAIChat(vc, didReceiveMessageEvent: ["action": action.rawValue, "payload": payload])

        case .openExternalUrl:
            if let urlString = payload["url"] as? String, let url = URL(string: urlString) {
                delegate?.loopsAIChat(vc, didRequestOpenURL: url)
            }

        case .requestTokenRefresh:
            vc.handleTokenRefreshRequest(requestId: message.requestId)

        case .respondingStateChange:
            let isResponding = (payload["isResponding"] as? Bool) ?? false
            delegate?.loopsAIChat(vc, isResponding: isResponding)

        case .productQuoteChanged:
            delegate?.loopsAIChat(vc, didChangeProductQuote: Self.parseQuote(payload))

        case .conversationActive:
            delegate?.loopsAIChatDidBecomeConversationActive(vc)

        case .newChatStarted:
            delegate?.loopsAIChat(vc, didReceiveMessageEvent: ["action": action.rawValue])

        case .overlayOpen, .overlayClosed:
            delegate?.loopsAIChat(vc, didReceiveMessageEvent: ["action": action.rawValue])

        case .ready, .persistSession, .trackEvent:
            break  // handled above
        }
    }

    private static func parseQuote(_ payload: [String: Any]) -> LoopsProductQuote? {
        // A null/empty product clears the quote.
        guard let product = payload["product"] as? [String: Any],
              let code = (product["code"] as? String) ?? (product["productCode"] as? String)
        else { return nil }
        return LoopsProductQuote(
            code: code,
            name: product["name"] as? String,
            image: product["image"] as? String,
            vtoEnabled: (product["vtoEnabled"] as? Bool) ?? false
        )
    }

    // MARK: - Outbound (native → web)

    func send(
        _ action: LoopsAIBridgeProtocol.NativeAction,
        payload: [String: Any] = [:],
        requestId: String? = nil,
        to webView: WKWebView
    ) {
        var envelope: [String: Any] = [
            "protocolVersion": LoopsAIBridgeProtocol.version,
            "type": LoopsAIBridgeProtocol.messageType,
            "name": action.rawValue,
            "payload": payload
        ]
        if let requestId { envelope["requestId"] = requestId }
        inject(envelope, into: webView)
    }

    func sendInitConfig(to webView: WKWebView, config: LoopsAIChatConfig) {
        // Merge any explicit flow-mode flag overrides; absent flags keep the
        // server-resolved agent config.
        var cfg: [String: Any] = ["alwaysShowCloseButton": false]
        for (key, value) in config.features.payload() { cfg[key] = value }
        send(.initConfig, payload: ["config": cfg], to: webView)
    }

    func sendInitContext(to webView: WKWebView, config: LoopsAIChatConfig) {
        send(.initContext, payload: config.initialContext?.toPayload() ?? [:], to: webView)
    }

    func sendUpdateContext(to webView: WKWebView, context: LoopsAIChatContext) {
        send(.updateContext, payload: context.toPayload(), to: webView)
    }

    private func inject(_ envelope: [String: Any], into webView: WKWebView) {
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope),
              let json = String(data: data, encoding: .utf8) else { return }

        // Deliver to the web runtime's window message listener (mode=sdk).
        let js = "window.postMessage(\(json), '*');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
