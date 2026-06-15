import Foundation
import UIKit

/// A product quote surfaced by the web runtime.
/// `nil` quote means the quote was cleared.
public struct LoopsProductQuote: Sendable, Equatable {
    public let code: String
    public let name: String?
    public let image: String?
    public let vtoEnabled: Bool

    public init(code: String, name: String? = nil, image: String? = nil, vtoEnabled: Bool = false) {
        self.code = code
        self.name = name
        self.image = image
        self.vtoEnabled = vtoEnabled
    }
}

/// Errors surfaced to the host through `loopsAIChat(_:didFailWith:)`.
public enum LoopsError: Error, Sendable {
    /// The WebView failed to load the chat runtime.
    case load(underlying: String)
    /// The bridge received a malformed or unsupported message.
    case bridge(reason: String)
    /// Session bootstrap (`/api/widget/session`) failed.
    case session(reason: String)
}

/// Host callbacks for a `LoopsAIChatViewController`.
/// All methods are optional — default no-op implementations are provided, except
/// the two navigation callbacks which keep their historical default behavior.
public protocol LoopsAIChatDelegate: AnyObject {
    /// The web runtime emitted `ready` — the bridge is live and context is applied.
    func loopsAIChatDidBecomeReady(_ viewController: LoopsAIChatViewController)

    /// A chat message event crossed the bridge (`newChatStarted` and message frames).
    func loopsAIChat(_ viewController: LoopsAIChatViewController, didReceiveMessageEvent event: [String: Any])

    /// The bot started (`true`) or stopped (`false`) responding.
    func loopsAIChat(_ viewController: LoopsAIChatViewController, isResponding: Bool)

    /// A canonical analytics event crossed the bridge.
    /// Delivered as-is — the SDK dictates the shape.
    func loopsAIChat(_ viewController: LoopsAIChatViewController, didEmitAnalyticsEvent event: LoopsAnalyticsEvent)

    /// The active product quote changed (`nil` when cleared).
    func loopsAIChat(_ viewController: LoopsAIChatViewController, didChangeProductQuote quote: LoopsProductQuote?)

    /// A conversation became active.
    func loopsAIChatDidBecomeConversationActive(_ viewController: LoopsAIChatViewController)

    /// The web runtime requested the container to close.
    func loopsAIChatDidRequestClose(_ viewController: LoopsAIChatViewController)

    /// A foreign link / `openExternalUrl` should open outside the WebView.
    func loopsAIChat(_ viewController: LoopsAIChatViewController, didRequestOpenURL url: URL)

    /// An unrecoverable error occurred (load / bridge / session).
    func loopsAIChat(_ viewController: LoopsAIChatViewController, didFailWith error: LoopsError)
}

public extension LoopsAIChatDelegate {
    func loopsAIChatDidBecomeReady(_ viewController: LoopsAIChatViewController) {}

    func loopsAIChat(_ viewController: LoopsAIChatViewController, didReceiveMessageEvent event: [String: Any]) {}

    func loopsAIChat(_ viewController: LoopsAIChatViewController, isResponding: Bool) {}

    func loopsAIChat(_ viewController: LoopsAIChatViewController, didEmitAnalyticsEvent event: LoopsAnalyticsEvent) {}

    func loopsAIChat(_ viewController: LoopsAIChatViewController, didChangeProductQuote quote: LoopsProductQuote?) {}

    func loopsAIChatDidBecomeConversationActive(_ viewController: LoopsAIChatViewController) {}

    func loopsAIChatDidRequestClose(_ viewController: LoopsAIChatViewController) {
        if viewController.navigationController != nil {
            viewController.navigationController?.popViewController(animated: true)
        } else {
            viewController.dismiss(animated: true)
        }
    }

    func loopsAIChat(_ viewController: LoopsAIChatViewController, didRequestOpenURL url: URL) {
        UIApplication.shared.open(url)
    }

    func loopsAIChat(_ viewController: LoopsAIChatViewController, didFailWith error: LoopsError) {}
}
