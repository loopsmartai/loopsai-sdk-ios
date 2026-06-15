# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-15

### Added

- **v2 bridge**: typed `nativeAction` envelope (`protocolVersion 1`),
  full web→native / native→web action allowlists, native session ownership
  (`_lsuid`/`_lscid` re-injection), `ready` handshake, and host
  callbacks (`onReady`/`onMessage`/`onResponding`/`onProductQuoteChanged`/
  `onConversationActive`/`onAnalyticsEvent`/`onError`). `LoopsEnvironment` enum.
- **New-conversation control**: `LoopsAIChatViewController.startNewConversation()`
  and `LoopsAIChatConfig(startFresh:)`. Loads with `fresh=true` and omits `_lscid`
  so the runtime starts a brand-new conversation instead of resuming the last one
  (local cache *and* the server's most-recent). Fixes entry points like "Ask AI"
  that should feel fresh, and gives hosts a real "new chat" action.
- **Flow modes**: `openWithSearch(_:productsOnly:)`,
  `startTryOnFromQuote()`, `openVoiceMode()`, `syncCustomerDetails(customerId:)`,
  `setWebsiteFont(_:)`; `LoopsFeatureFlags` forwarded via `initConfig`;
  `WKUIDelegate` microphone-capture grant for voice (host must add
  `NSMicrophoneUsageDescription`).
- **Embed parity actions**: `clearProductQuote()` (drop the active quote chip),
  `closeOverlays()` (close a web overlay — VTO/size/sidebar — without unloading the
  WebView, e.g. on a back gesture), and automatic `mobileStateChange` on
  rotation/size-class change (compact = `horizontalSizeClass == .compact`). Closes
  the remaining gap vs the web embed's host→iframe action set.
- **Native analytics**: `LoopsAnalyticsEvent` (canonical, forced
  `channel:"mobile_app"`), `LoopsAnalyticsDispatcher` (always-on `LoopsSinkAdapter`
  + optional customer adapter), `HttpWebhookAdapter`, `BlockAnalyticsAdapter`
  (decouples Firebase/Mixpanel/Segment), `LoopsAnalyticsConfig`.
- **Host-emitted native events**: public `LoopsAnalyticsEvent(event:params:context:)`
  initializer + public `LoopsAnalyticsDispatcher.dispatch(_:)`, so a host app can
  push its own canonical events (e.g. a commerce funnel — `add_to_cart`,
  `begin_checkout`, `purchase`) through the same sink the bridge uses. Mirrors the
  web dispatcher's `trackCanonicalEvent`.
- **Cache & Reset Control**: `LoopsAIChat.resetAllData()` for a complete data wipe (session store + cookies, localStorage, IndexedDB) and `LoopsAIChat.clearWebCache()` to purge kept-alive WebViews from memory.

### Changed

- **`openWithSearch(_:productsOnly:)` now defaults `productsOnly` to `true`** —
  matching the web embed's `openWithSearch` (`isOnlySearchProducts: true`). The old
  default (`false`) escalated the query into the conversation, so an "AI search"
  surfaced as an ordinary chat message instead of product results. Pass `false`
  explicitly for the conversational-escalation behavior.
- **Session storage** moved from Keychain to `UserDefaults` — the correct medium
  for a pseudonymous id: it survives app relaunch (the iOS WebKit storage-loss bug
  we fix) but is cleared on uninstall, so a reinstall starts a clean identity
  rather than resurrecting the old id + conversation history.
- Strict-concurrency: `LoopsAnalyticsAdapter`/`LoopsAnalyticsDispatcher`/
  `LoopsAnalyticsConfig`/`LoopsAIChatConfig` are now `Sendable`.
- Session bootstrap retries transient failures (5xx / transport) with exponential
  backoff (3 attempts) instead of a single-shot POST.
- Added DocC doc comments and accessibility labels/hints.

## [0.1.0] - 2026-03-27

### Added

- `LoopsAIChatConfig` — configuration with agentId, context, locale, and baseURL.
- `LoopsAIChatContext` — typed context model for productContext and userContext.
- `LoopsAIChatDelegate` — protocol for receiving close and openURL requests.
- `LoopsAIChatBridge` — WKScriptMessageHandler matching the B2C postMessage contract.
- `LoopsAIChatViewController` — UIKit core with WKWebView, loading/error states, and convenience methods.
- `LoopsAIChat` — static API for modal presentation and navigation push.
- `LoopsAIChatView` — SwiftUI wrapper via `UIViewControllerRepresentable`.
- Convenience methods: `sendMessage(_:)`, `suggestSize()`, `startVirtualTryOn(product:)`.
