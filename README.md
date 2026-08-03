# Loops AI Chat SDK for iOS

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-lightgrey.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

The official iOS SDK for [Loops AI](https://loopsai.com) — a thin native container
that embeds the Loops AI chat experience (chat, virtual try-on, AI search, size
guidance) into any iOS app. The web runtime owns the conversation UI;
**native owns the session, routing, and analytics**. UIKit + SwiftUI.

---

## Installation

### Swift Package Manager (Xcode)

1. **File → Add Package Dependencies**
2. Enter `https://github.com/loopsmartai/loopsai-sdk-ios.git`
3. Add **`LoopsAIChatSDK`** to your target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/loopsmartai/loopsai-sdk-ios.git", from: "1.0.2")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "LoopsAIChatSDK", package: "loopsai-sdk-ios")
    ])
]
```

---

## Quick start

### SwiftUI

```swift
import SwiftUI
import LoopsAIChatSDK

struct ContentView: View {
    @State private var isChatOpen = false
    let config = LoopsAIChatConfig(agentId: "YOUR_AGENT_ID")

    var body: some View {
        Button("Open Chat") { isChatOpen = true }
            .fullScreenCover(isPresented: $isChatOpen) {
                LoopsAIChatView(config: config, onClose: { isChatOpen = false })
                    .ignoresSafeArea()
            }
    }
}
```

### UIKit

```swift
import LoopsAIChatSDK

let config = LoopsAIChatConfig(agentId: "YOUR_AGENT_ID")
LoopsAIChat.present(from: self, config: config)
```

---

## Configuration

`LoopsAIChatConfig` is the single entry point:

| Parameter | Type | Default | Description |
|---|---|---|---|
| `agentId` | `String` | — | Your Loops AI agent identifier (required). |
| `environment` | `LoopsEnvironment` | `.production` | `.production` (chat.loopsai.com) or `.custom(URL)` (on-prem). |
| `initialContext` | `LoopsAIChatContext?` | `nil` | Product / user context at launch. |
| `features` | `LoopsFeatureFlags` | `.default` | Per-launch flow-mode overrides. |
| `analytics` | `LoopsAnalyticsConfig` | `.default` | Sink + customer analytics destinations. |
| `locale` | `String?` | `nil` | Language code, e.g. `"en"`, `"tr"`. |
| `showCloseButton` | `Bool` | `true` | Native close button (top-right). |

### Environments

```swift
LoopsAIChatConfig(agentId: "…", environment: .production)      // chat.loopsai.com
LoopsAIChatConfig(agentId: "…", environment: .custom(URL(string: "https://chat.acme.com")!))
```

The custom host is automatically added to the bridge origin allowlist.

---

## Context

Personalize the conversation with product and user context — at launch or live:

```swift
let config = LoopsAIChatConfig(
    agentId: "YOUR_AGENT_ID",
    initialContext: LoopsAIChatContext(
        productContext: ["productCode": "SKU-123", "productName": "Linen Shirt"],
        userContext:    ["userId": "u_42", "firstName": "Ada"]
    )
)

// Update later (e.g. on product navigation):
chatVC.updateContext(LoopsAIChatContext(productContext: ["productCode": "SKU-456"]))
```

---

## Flow modes

Drive native entry points on `LoopsAIChatViewController` (call after the bridge is
ready — see the delegate's `loopsAIChatDidBecomeReady`):

```swift
chatVC.sendMessage("I need help with sizing")
chatVC.suggestSize()
chatVC.startVirtualTryOn(product: ["productCode": "SKU-123"])
chatVC.startTryOnFromQuote()                 // try on the currently quoted product
chatVC.openWithSearch("summer dress")        // AI search; productsOnly: true to restrict
chatVC.syncCustomerDetails(customerId: "cust_42")  // enrich session with a known customer
chatVC.setWebsiteFont("Inter, sans-serif")    // match chat typography to your app
```

Flow modes the server config disables are ignored. Override per launch with
`LoopsFeatureFlags`:

```swift
let config = LoopsAIChatConfig(
    agentId: "…",
    features: LoopsFeatureFlags(searchEscalationEnabled: true, virtualTryOnEnabled: true)
)
```

Unset flags defer to the server-resolved agent config.

---

## Delegate & callbacks

`LoopsAIChatDelegate` surfaces bridge events. All methods are optional.

| Method | Description |
|---|---|
| `loopsAIChatDidBecomeReady(_:)` | Bridge is live — safe to drive flow modes. |
| `loopsAIChat(_:didReceiveMessageEvent:)` | A chat message / module event crossed the bridge. |
| `loopsAIChat(_:isResponding:)` | The assistant started/stopped responding. |
| `loopsAIChat(_:didEmitAnalyticsEvent:)` | A canonical analytics event (`LoopsAnalyticsEvent`). |
| `loopsAIChat(_:didChangeProductQuote:)` | The active product quote changed (`nil` = cleared). |
| `loopsAIChatDidBecomeConversationActive(_:)` | A conversation became active. |
| `loopsAIChatDidRequestClose(_:)` | The runtime asked to close. |
| `loopsAIChat(_:didRequestOpenURL:)` | A foreign link should open outside the WebView. |
| `loopsAIChat(_:didFailWith:)` | An unrecoverable error (`load` / `bridge` / `session`). |

SwiftUI exposes the same via closures on `LoopsAIChatView` (`onReady`,
`onResponding`, `onProductQuoteChanged`, `onAnalyticsEvent`, `onClose`,
`onOpenURL`, `onError`).

---

## Analytics

Analytics flow through the SDK on the **`ios`** channel, so app and web
reports share one taxonomy. The web runtime emits canonical events; the SDK
re-dispatches them natively (forcing `channel: "ios"` + `app_version` /
`device` / `os_version`) to an always-on Loops sink plus your optional adapter.

```swift
let analytics = LoopsAnalyticsConfig(
    loopsSinkEndpoint: URL(string: "https://<your-ingest-endpoint>"),
    customerAdapter: HttpWebhookAdapter(endpoint: URL(string: "https://acme.com/collect")!)
)
let config = LoopsAIChatConfig(agentId: "…", analytics: analytics)
```

Built-in adapters: `LoopsSinkAdapter` (always-on), `HttpWebhookAdapter` (generic
POST), `BlockAnalyticsAdapter` (closure — wire Firebase/Mixpanel/Segment without
a core dependency).

```swift
let firebase = BlockAnalyticsAdapter(id: "firebase") { event in
    Analytics.logEvent(event.event, parameters: event.payload as? [String: Any])
}
```

### Emit your own native events

Push your app's own canonical events (e.g. a commerce funnel) through the same
pipeline — the native equivalent of the web `trackCanonicalEvent`:

```swift
let dispatcher = LoopsAnalyticsDispatcher(
    sink: LoopsSinkAdapter(endpoint: sinkURL),
    customer: nil
)
let event = LoopsAnalyticsEvent(
    event: "purchase",
    params: ["currency": "TRY", "value": 1299,
             "ecommerce": ["items": [["item_id": "SKU-123", "quantity": 1]]]],
    context: LoopsAnalyticsContext(locale: "en")
)
dispatcher.dispatch(event)   // forces channel:"ios" + native context
```

---

## Native session

The SDK owns the anonymous session natively (Keychain) and re-injects it on every
WebView load, fixing the iOS WebKit storage-loss class of bugs (`mode=sdk`). It
bootstraps against `POST /api/widget/session` with retry/backoff. No tokens or
credentials are stored — only a pseudonymous anon id.

---

## Presentation (UIKit)

```swift
LoopsAIChat.present(from: self, config: config, style: .fullScreen)
LoopsAIChat.present(from: self, config: config, style: .sheet())            // swipe-dismiss
LoopsAIChat.present(from: self, config: config, style: .sheet(.locked))     // close button only
LoopsAIChat.present(from: self, config: config, style: .sheet(.interactive))// large + medium
LoopsAIChat.push(from: navigationController, config: config)
```

SwiftUI uses native `.fullScreenCover` / `.sheet` modifiers around `LoopsAIChatView`.

---

## Availability (server-controlled on/off)

Turn chat on/off from the dashboard **without an app update** — the iOS channel
has its own Active/Passive toggle in the Channels tab, independent of web and
Android. While the iOS channel is unset (never configured), availability falls
back to the web channel's `embedEnabled` gate. Query it before showing your
chat entry point:

```swift
LoopsAIChat.fetchAvailability(agentId: "your_agent_id") { available in
    chatButton.isHidden = !available
}
```

Use this to keep chat off at release and flip it on later, or disable it for
maintenance. It fails **open** (`true`) on a network error, so a transient blip
never hides a working chat. For staging/QA builds that must load even while the
channel is inactive, set `developmentMode: true` (or `designMode: true`) on the
config.

---

## Requirements

- iOS 15.0+ · Swift 5.9+ · Xcode 15.0+

## Security

- The WebView only loads Loops-owned (or your configured custom) origins.
- External links open in the system browser, never inside the SDK WebView.
- Bridge communication is origin-allowlisted and main-frame only.
- No credentials or tokens are stored on device.

## License

Proprietary — see [LICENSE](LICENSE).
