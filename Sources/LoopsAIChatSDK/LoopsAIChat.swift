import UIKit
import WebKit

/// Entry point for presenting the Loops AI chat experience.
///
/// Use ``present(from:config:style:delegate:)`` to show the chat modally
/// (full-screen or as a sheet) or ``push(from:config:delegate:)`` to push it
/// onto a navigation stack. For SwiftUI, use ``LoopsAIChatView`` instead.
public enum LoopsAIChat {

    /// Present the chat from a host view controller.
    /// - Parameters:
    ///   - viewController: the presenting view controller.
    ///   - config: agent id, environment, context, feature flags, analytics.
    ///   - style: `.fullScreen`, `.sheet(_:)`, or `.push`.
    ///   - delegate: optional host callbacks (ready/message/responding/quote/error).
    /// - Returns: the created ``LoopsAIChatViewController`` for further driving.
    @discardableResult
    public static func present(
        from viewController: UIViewController,
        config: LoopsAIChatConfig,
        style: LoopsAIChatPresentationStyle = .fullScreen,
        delegate: LoopsAIChatDelegate? = nil
    ) -> LoopsAIChatViewController {
        let chatVC = LoopsAIChatViewController(config: config, delegate: delegate)

        switch style {
        case .fullScreen:
            chatVC.modalPresentationStyle = .fullScreen

        case .sheet(let sheetConfig):
            chatVC.modalPresentationStyle = .pageSheet
            if let sheet = chatVC.sheetPresentationController {
                sheet.detents = sheetConfig.detents
                sheet.prefersGrabberVisible = sheetConfig.prefersGrabberVisible
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
            chatVC.isModalInPresentation = !sheetConfig.isInteractiveDismissEnabled

        case .push:
            guard let nav = viewController.navigationController else {
                chatVC.modalPresentationStyle = .fullScreen
                viewController.present(chatVC, animated: true)
                return chatVC
            }
            nav.pushViewController(chatVC, animated: true)
            return chatVC
        }

        viewController.present(chatVC, animated: true)
        return chatVC
    }

    @discardableResult
    public static func push(
        from navigationController: UINavigationController,
        config: LoopsAIChatConfig,
        delegate: LoopsAIChatDelegate? = nil
    ) -> LoopsAIChatViewController {
        let chatVC = LoopsAIChatViewController(config: config, delegate: delegate)
        navigationController.pushViewController(chatVC, animated: true)
        return chatVC
    }

    /// Drop every kept-alive chat runtime (the warm `WKWebView` pool). Call on
    /// logout / account switch, or under memory pressure, so the next presentation
    /// cold-loads fresh. The shared HTTP cache / cookies / localStorage in the
    /// persistent data store are unaffected — use ``resetAllData(completion:)`` for
    /// a full data wipe.
    public static func clearWebCache() {
        LoopsChatWebViewPool.shared.purgeAll()
    }

    /// Erase **all** chat state in one shot — for a "reset" / logout / account
    /// switch. This:
    /// 1. drops every warm `WKWebView` (so no live runtime survives),
    /// 2. clears the native anon session (`LoopsSessionStore.reset()`), and
    /// 3. removes the web runtime's persisted data (cookies, localStorage,
    ///    IndexedDB, caches) from the default `WKWebsiteDataStore`.
    ///
    /// After this the next presentation cold-loads a brand-new pseudonymous
    /// identity and conversation. Safe to call from the main thread.
    /// - Parameters:
    ///   - sessionStore: the store to wipe (defaults to a fresh `UserDefaults`-backed
    ///     store — correct when the host lets the SDK own the session).
    ///   - completion: called on the main thread once the website data is cleared.
    public static func resetAllData(
        sessionStore: LoopsSessionStore = LoopsSessionStore(),
        completion: (() -> Void)? = nil
    ) {
        LoopsChatWebViewPool.shared.purgeAll()
        sessionStore.reset()

        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) {
            if Thread.isMainThread {
                completion?()
            } else {
                DispatchQueue.main.async { completion?() }
            }
        }
    }
}
