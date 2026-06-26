# Loops AI Chat SDK for iOS

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2015%2B-lightgrey.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)

The official iOS SDK for [Loops AI](https://loopsai.com). A native container that
embeds the Loops AI conversational commerce experience into any iOS app — chat,
virtual try-on, AI product search, and size guidance. The web runtime owns the
conversation UI; native owns the session, routing, and analytics. UIKit + SwiftUI.

---

## Installation

### Swift Package Manager (Xcode)

1. **File → Add Package Dependencies**
2. Enter `https://github.com/loopsmartai/loopsai-sdk-ios.git`
3. Add **`LoopsAIChatSDK`** to your target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/loopsmartai/loopsai-sdk-ios.git", from: "1.0.0")
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
| `environment` | `LoopsEnvironment` | `.production` | `.production` or `.custom(URL)`. |
| `initialContext` | `LoopsAIChatContext?` | `nil` | Product / user context at launch. |
| `features` | `LoopsFeatureFlags` | `.default` | Per-launch flow-mode overrides. |
| `analytics` | `LoopsAnalyticsConfig` | `.default` | Sink + customer analytics destinations. |
| `locale` | `String?` | `nil` | Language code, e.g. `"en"`, `"tr"`. |
| `showCloseButton` | `Bool` | `true` | Native close button (top-right). |
| `keepAliveEnabled` | `Bool` | `true` | Keep the `WKWebView` warm between presentations for instant reopen. |
| `startFresh` | `Bool` | `false` | Start a new conversation instead of resuming the last one. |

### Environments

```swift
LoopsAIChatConfig(agentId: "…", environment: .production)
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

chatVC.updateContext(LoopsAIChatContext(productContext: ["productCode": "SKU-456"]))
```

---

## Flow modes

Native entry points on `LoopsAIChatViewController`. Call after the bridge is
ready (`loopsAIChatDidBecomeReady`):

```swift
chatVC.sendMessage("I need help with sizing")
chatVC.suggestSize()
chatVC.startVirtualTryOn(product: ["productCode": "SKU-123"])
chatVC.quoteProduct(product: ["productCode": "SKU-123"])
chatVC.clearProductQuote()
chatVC.startTryOnFromQuote()
chatVC.openWithSearch("summer dress")
chatVC.syncCustomerDetails(customerId: "cust_42")
chatVC.setWebsiteFont("Inter, sans-serif")
chatVC.startNewConversation()
chatVC.setAnalyticsConsent(true)
chatVC.closeOverlays()
```

Flow modes the server config disables are safely ignored. Override per launch
with `LoopsFeatureFlags`:

```swift
let config = LoopsAIChatConfig(
    agentId: "…",
    features: LoopsFeatureFlags(virtualTryOnEnabled: true)
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

Analytics flow through the SDK on the **`mobile_app`** channel. The web runtime
emits canonical events; the SDK re-dispatches them natively with
`channel: "mobile_app"` and native context (`app_version`, `device`,
`os_version`), so app and web reports share one taxonomy.

Built-in adapters: `LoopsSinkAdapter` (always-on), `HttpWebhookAdapter` (generic
POST), `BlockAnalyticsAdapter` (closure — wire Firebase / Mixpanel / Segment
without a core dependency).

```swift
let firebase = BlockAnalyticsAdapter(id: "firebase") { event in
    Analytics.logEvent(event.event, parameters: event.payload as? [String: Any])
}
let config = LoopsAIChatConfig(
    agentId: "…",
    analytics: LoopsAnalyticsConfig(customerAdapter: firebase)
)
```

---

## Native session

The SDK owns the anonymous session natively (`UserDefaults`) and re-injects it on
every WebView load, fixing the iOS WebKit storage-loss class of bugs. Session
bootstrap runs automatically with retry and exponential backoff. No credentials
are stored — only a pseudonymous anon id.

### Resetting data

```swift
LoopsAIChat.clearWebCache()

LoopsAIChat.resetAllData {
    // completed on the main thread
}
```

---

## Presentation (UIKit)

```swift
LoopsAIChat.present(from: self, config: config, style: .fullScreen)
LoopsAIChat.present(from: self, config: config, style: .sheet())
LoopsAIChat.present(from: self, config: config, style: .sheet(.locked))
LoopsAIChat.present(from: self, config: config, style: .sheet(.interactive))
LoopsAIChat.push(from: navigationController, config: config)
```

SwiftUI uses native `.fullScreenCover` / `.sheet` modifiers around `LoopsAIChatView`.

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
