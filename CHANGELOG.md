# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — server-controlled availability

- **`LoopsAIChat.fetchAvailability(agentId:)`** — reports whether the agent is
  active for this platform. Reads the iOS channel's own Active/Passive status and
  falls back to the web channel when the iOS channel is unset, so hosts can show/
  hide their chat entry point and toggle iOS independently of web and Android from
  the dashboard, without an app update. Fails open on network errors.
- **`developmentMode` / `designMode`** config flags — load the runtime even when
  the channel is inactive (staging / QA / design preview).

### Changed

- **Analytics channel is now `"ios"`** (was `"mobile_app"`): canonical events are
  relabelled with the per-platform channel, following the platform split of the
  former single mobile channel. Events also carry a **`kind`** field
  (`"ecommerce"` | `"interaction"`) discriminating canonical ecommerce events
  from customer-interaction events; it defaults to `"ecommerce"` when absent.
- **Production-only environment**: the SDK now targets `chat.loopsai.com`
  everywhere. `LoopsEnvironment.test` was removed; `.production` and `.custom(URL)`
  remain. Keeps the iOS and Android SDKs in lockstep.

### Removed

- **Voice mode** is no longer exposed: the `openVoiceMode()` entry point and the
  `voiceModeEnabled` / `speechToTextEnabled` feature flags were removed (the
  `startVoiceMode` bridge action is retained internally, server-gated).

## [1.0.0] - 2026-06-15

### Added

- **v2 bridge** (TASK-0014): typed `nativeAction` envelope (`protocolVersion 1`),
  full web→native / native→web action allowlists, native session ownership
  (`_lsuid`/`_lscid` re-injection), `ready` handshake, and host
  callbacks (`onReady`/`onMessage`/`onResponding`/`onProductQuoteChanged`/
  `onConversationActive`/`onAnalyticsEvent`/`onError`). `LoopsEnvironment` enum.
- **New-conversation control**: `LoopsAIChatViewController.startNewConversation()`
  and `LoopsAIChatConfig(startFresh:)`. Loads with `fresh=true` and omits `_lscid`
  so the runtime starts a brand-new conversation instead of resuming the last one
  (local cache *and* the server's most-recent). Fixes entry points like "Ask AI"
  that should feel fresh, and gives hosts a real "new chat" action.
- **Flow modes** (TASK-0016): `openWithSearch(_:productsOnly:)`,
  `startTryOnFromQuote()`, `openVoiceMode()`, `syncCustomerDetails(customerId:)`,
  `setWebsiteFont(_:)`; `LoopsFeatureFlags` forwarded via `initConfig`;
  `WKUIDelegate` microphone-capture grant for voice (host must add
  `NSMicrophoneUsageDescription`).
- **Embed parity actions**: `clearProductQuote()` (drop the active quote chip),
  `closeOverlays()` (close a web overlay — VTO/size/sidebar — without unloading the
  WebView, e.g. on a back gesture), and automatic `mobileStateChange` on
  rotation/size-class change (compact = `horizontalSizeClass == .compact`). Closes
  the remaining gap vs the web embed's host→iframe action set (CONTRACT B.3).
- **Native analytics** (TASK-0015): `LoopsAnalyticsEvent` (canonical, forced
  `channel:"mobile_app"`), `LoopsAnalyticsDispatcher` (always-on `LoopsSinkAdapter`
  + optional customer adapter), `HttpWebhookAdapter`, `BlockAnalyticsAdapter`
  (decouples Firebase/Mixpanel/Segment), `LoopsAnalyticsConfig`.
- **Host-emitted native events**: public `LoopsAnalyticsEvent(event:params:context:)`
  initializer + public `LoopsAnalyticsDispatcher.dispatch(_:)`, so a host app can
  push its own canonical events (e.g. a commerce funnel — `add_to_cart`,
  `begin_checkout`, `purchase`) through the same sink the bridge uses. Mirrors the
  web dispatcher's `trackCanonicalEvent`.

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
