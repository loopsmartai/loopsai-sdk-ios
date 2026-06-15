import SwiftUI

/// SwiftUI wrapper around ``LoopsAIChatViewController``. Provide a
/// ``LoopsAIChatConfig`` and opt into host callbacks via the closures
/// (`onReady`, `onResponding`, `onProductQuoteChanged`, `onAnalyticsEvent`,
/// `onError`, …). Present it in a sheet or full-screen cover.
public struct LoopsAIChatView: UIViewControllerRepresentable {

    public class Coordinator: LoopsAIChatDelegate {
        var onClose: (() -> Void)?
        var onOpenURL: ((URL) -> Void)?
        var onReady: (() -> Void)?
        var onResponding: ((Bool) -> Void)?
        var onProductQuoteChanged: ((LoopsProductQuote?) -> Void)?
        var onAnalyticsEvent: ((LoopsAnalyticsEvent) -> Void)?
        var onError: ((LoopsError) -> Void)?

        init(
            onClose: (() -> Void)?,
            onOpenURL: ((URL) -> Void)?,
            onReady: (() -> Void)?,
            onResponding: ((Bool) -> Void)?,
            onProductQuoteChanged: ((LoopsProductQuote?) -> Void)?,
            onAnalyticsEvent: ((LoopsAnalyticsEvent) -> Void)?,
            onError: ((LoopsError) -> Void)?
        ) {
            self.onClose = onClose
            self.onOpenURL = onOpenURL
            self.onReady = onReady
            self.onResponding = onResponding
            self.onProductQuoteChanged = onProductQuoteChanged
            self.onAnalyticsEvent = onAnalyticsEvent
            self.onError = onError
        }

        public func loopsAIChatDidRequestClose(_ viewController: LoopsAIChatViewController) {
            onClose?()
        }

        public func loopsAIChat(_ viewController: LoopsAIChatViewController, didRequestOpenURL url: URL) {
            if let handler = onOpenURL {
                handler(url)
            } else {
                UIApplication.shared.open(url)
            }
        }

        public func loopsAIChatDidBecomeReady(_ viewController: LoopsAIChatViewController) {
            onReady?()
        }

        public func loopsAIChat(_ viewController: LoopsAIChatViewController, isResponding: Bool) {
            onResponding?(isResponding)
        }

        public func loopsAIChat(_ viewController: LoopsAIChatViewController, didChangeProductQuote quote: LoopsProductQuote?) {
            onProductQuoteChanged?(quote)
        }

        public func loopsAIChat(_ viewController: LoopsAIChatViewController, didEmitAnalyticsEvent event: LoopsAnalyticsEvent) {
            onAnalyticsEvent?(event)
        }

        public func loopsAIChat(_ viewController: LoopsAIChatViewController, didFailWith error: LoopsError) {
            onError?(error)
        }
    }

    private let config: LoopsAIChatConfig
    private var onClose: (() -> Void)?
    private var onOpenURL: ((URL) -> Void)?
    private var onReady: (() -> Void)?
    private var onResponding: ((Bool) -> Void)?
    private var onProductQuoteChanged: ((LoopsProductQuote?) -> Void)?
    private var onAnalyticsEvent: ((LoopsAnalyticsEvent) -> Void)?
    private var onError: ((LoopsError) -> Void)?

    public init(
        config: LoopsAIChatConfig,
        onClose: (() -> Void)? = nil,
        onOpenURL: ((URL) -> Void)? = nil,
        onReady: (() -> Void)? = nil,
        onResponding: ((Bool) -> Void)? = nil,
        onProductQuoteChanged: ((LoopsProductQuote?) -> Void)? = nil,
        onAnalyticsEvent: ((LoopsAnalyticsEvent) -> Void)? = nil,
        onError: ((LoopsError) -> Void)? = nil
    ) {
        self.config = config
        self.onClose = onClose
        self.onOpenURL = onOpenURL
        self.onReady = onReady
        self.onResponding = onResponding
        self.onProductQuoteChanged = onProductQuoteChanged
        self.onAnalyticsEvent = onAnalyticsEvent
        self.onError = onError
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onClose: onClose,
            onOpenURL: onOpenURL,
            onReady: onReady,
            onResponding: onResponding,
            onProductQuoteChanged: onProductQuoteChanged,
            onAnalyticsEvent: onAnalyticsEvent,
            onError: onError
        )
    }

    public func makeUIViewController(context: Context) -> LoopsAIChatViewController {
        LoopsAIChatViewController(config: config, delegate: context.coordinator)
    }

    public func updateUIViewController(_ uiViewController: LoopsAIChatViewController, context: Context) {
        let c = context.coordinator
        c.onClose = onClose
        c.onOpenURL = onOpenURL
        c.onReady = onReady
        c.onResponding = onResponding
        c.onProductQuoteChanged = onProductQuoteChanged
        c.onAnalyticsEvent = onAnalyticsEvent
        c.onError = onError
        uiViewController.delegate = c
    }
}
