# AttributionKit

Lightweight iOS attribution SDK that resolves install source via a 3-step waterfall: **Apple Search Ads → fingerprint match → cached UTM → organic fallback**. Pairs with a Fastify backend that stores attribution and joins it to revenue events from a subscription provider's webhooks.

- **Platform:** iOS 15+
- **Swift:** 5.9
- **Dependencies:** none

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/CyonCode/attribution-ios-sdk", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: ["AttributionKit"]),
]
```

## Quick start

```swift
import AttributionKit

// At launch (e.g. AppDelegate or @main App.init)
AttributionKit.shared.configure(
    apiKey:  "<product api_key from server /admin>",
    appId:   "<product app_id from server /admin>",
    baseURL: "https://attribution.your-domain.com"
)
AttributionKit.shared.performAttributionIfNeeded()
```

That's it for **install attribution**. The SDK handles ASA → fingerprint → UTM → organic resolution and reports to your backend, which stores it under `(app_id, idfv)`.

## UTM tracking

If you ship Universal Links from your landing pages, hand the URL to the SDK:

```swift
.onOpenURL { url in
    AttributionKit.shared.handleUniversalLink(url)
}
```

UTM params (`utm_source`, `utm_medium`, `utm_campaign`, `utm_content`) are cached locally and merged into attribution if ASA returns nothing.

---

## Revenue tracking

Attribution alone tells you *where users came from*. To know *what they spent*, the backend ingests revenue webhooks from your subscription provider. The SDK does **not** receive purchase events directly — that's by design (account-of-record is the App Store, surfaced through Qonversion or Adapty).

> **Pick one provider.** Running both Qonversion and Adapty against the same App Store account will double-count revenue. The dedup keys are scoped per-`provider`, so the server cannot collapse a duplicate purchase that arrives from two different SDKs.

This guide uses **Qonversion** as the reference integration. See [Examples/RevenueIntegration.swift](Examples/RevenueIntegration.swift) for the complete copy-pasteable file.

### How attribution joins to revenue

The backend joins `Revenue.external_user_id` to `Attribution.idfv`. **AttributionKit already uploads IDFV as its identifier**, so the only thing you need to do app-side is make sure your subscription SDK reports the same IDFV as its user id.

```
[Your App]                                       [Attribution Server]

AttributionKit.performAttributionIfNeeded()  →   Attribution.idfv = <IDFV>
                                                          ↕   (join key)
Qonversion.setUserProperty(.userID, <IDFV>)  →   Revenue.external_user_id = <IDFV>
```

If these two values don't match, revenue events are still recorded but tagged `attribution_source = 'unknown'` and you lose LTV-by-source resolution.

### Integration steps (Qonversion)

#### 1 — App-side: identify the user with IDFV

```swift
import AttributionKit
import Qonversion
import UIKit

func setupAttributionAndPurchases() {
    // Attribution
    AttributionKit.shared.configure(
        apiKey:  "<api_key>",
        appId:   "<app_id>",
        baseURL: "https://attribution.your-domain.com"
    )
    AttributionKit.shared.performAttributionIfNeeded()

    // Qonversion
    let config = Qonversion.Configuration(
        projectKey: "<your-qonversion-project-key>",
        launchMode: .subscriptionManagement
    )
    Qonversion.initWithConfig(config)

    // ⚠️ The single most important line for revenue attribution:
    // align Qonversion's customUserId with AttributionKit's idfv.
    if let idfv = UIDevice.current.identifierForVendor?.uuidString {
        Qonversion.shared().setUserProperty(.userID, value: idfv)
    }
}
```

Call once on app launch, **before** any purchase flow runs.

#### 2 — Server-side: configure webhook secret

```bash
# server/.env
QONVERSION_WEBHOOK_TOKEN=<long-random-string>
```

Restart the server. Hitting the webhook without this set returns `500 webhook_not_configured`.

#### 3 — Qonversion dashboard: register webhook

- Open Qonversion → **Project Settings → Integrations → Webhooks**
- URL: `https://attribution.your-domain.com/v1/webhook/qonversion/<your-appId>`
- Auth: **Basic Auth**, token = the `QONVERSION_WEBHOOK_TOKEN` value from step 2
- Events: enable all subscription + in-app events (the server's normalizer maps 16 Qonversion event names into a unified schema; unsupported events are acked-and-ignored)

#### 4 — Verify

Make a sandbox purchase. Within ~10 seconds, you should see a fresh document in MongoDB:

```js
db.revenues.find().sort({ createdAt: -1 }).limit(1).pretty()

// → provider:           'qonversion'
//   external_user_id:   '<your IDFV>'
//   event_type:         'initial_purchase' | 'trial_started' | ...
//   amount_usd:          0.99
//   attribution_source: 'asa' | 'organic' | 'tiktok' | ...      ← if 'unknown', step 1 didn't fire in time
```

If `attribution_source === 'unknown'`, the IDFV alignment didn't fire before purchase. Confirm `Qonversion.shared().setUserProperty(.userID, …)` runs at app launch, not lazily on the paywall screen.

---

## Notes & gotchas

- **IDFV resets on app reinstall.** Renewals after a reinstall produce a new `custom_user_id` that no longer matches the original `Attribution.idfv`. Renewal events get tagged `attribution_source = 'unknown'`. If renewal-LTV matters, add a server-side fallback that looks up the original `attribution_*` snapshot via `original_transaction_id`.
- **ATT prompt.** IDFV is available without ATT consent and is stable per (vendor, device), so attribution does not require ATT.
- **Sandbox vs Production.** Each Revenue document carries `environment`. Filter sandbox events out of LTV queries.
- **`distinctIdProvider`** in `configure(...)` is only used to attach an analytics distinct_id (e.g. PostHog) to attribution requests for downstream identify. It does **not** affect the revenue join — that always uses IDFV.
- **No tests yet.** `Tests/AttributionKitTests/` is a placeholder.

## File map

```
ios-sdk/
├── Sources/AttributionKit/         # SDK source
├── Examples/
│   └── RevenueIntegration.swift    # Copy-pasteable reference integration
├── Tests/AttributionKitTests/      # Placeholder
├── Package.swift
├── README.md                       # ← you are here
└── AGENTS.md                       # internal dev notes
```
