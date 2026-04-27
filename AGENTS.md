# AttributionKit

## OVERVIEW

Swift Package for iOS 15+. Resolves install attribution source via a 3-step waterfall: Apple Search Ads → fingerprint match → cached UTM → organic fallback.

## STRUCTURE

```
AttributionKit/
├── Package.swift
├── Sources/AttributionKit/
│   ├── AttributionKit.swift      # Public API — singleton, configure(), performAttributionIfNeeded()
│   ├── AttributionEngine.swift   # Core logic — ASA/fingerprint/UTM resolution + retry
│   ├── AttributionNetwork.swift  # HTTP client — POST to backend API
│   ├── AttributionConfig.swift   # Config struct (apiKey, appId, baseURL, distinctIdProvider)
│   ├── AttributionDelegate.swift # Callback protocol
│   └── AttributionResult.swift   # Result model (source, campaign, medium, content, rawPayload)
└── Tests/AttributionKitTests/    # Placeholder only
```

## WHERE TO LOOK

| Task | File | Notes |
|------|------|-------|
| Add new attribution source | `AttributionEngine.swift` | Insert step in waterfall chain |
| Change API contract | `AttributionNetwork.swift` | Request/response encoding |
| Modify public API | `AttributionKit.swift` | Singleton facade; `configure(..., distinctIdProvider:)` accepts a closure so host app can inject e.g. idfv or PostHog distinctId for server-side identify |
| Add callback data | `AttributionResult.swift` | Public result model |
| User-facing integration guide | `README.md` + `Examples/RevenueIntegration.swift` | Qonversion revenue integration walkthrough; SDK ships with a single chosen provider example (Qonversion), Adapty kept as commented-out alternative |

## CONVENTIONS

- **Singleton**: `AttributionKit.shared` — configure once, call `performAttributionIfNeeded()` on app launch
- **One-shot**: Attribution runs once per install (`ak_attribution_completed` in UserDefaults/@AppStorage)
- **ASA retry**: 3 attempts with exponential backoff [1, 2, 4] seconds
- **Thread safety**: `NSLock` guards `isRunning`/`attributionCompleted` state
- **UTM caching**: `handleUniversalLink()` extracts UTM params and caches in UserDefaults
- **distinctIdProvider**: optional closure in `configure(...)`. Evaluated lazily at each request build site so identify-time changes in host app's analytics SDK are picked up. Server uses this to call PostHog `identify()` and link attribution → revenue webhooks.
- **Platform guards**: `#if os(iOS)` for @AppStorage, `#if canImport(AdServices)` for ASA

## ANTI-PATTERNS

- Don't call `performAttributionIfNeeded()` before `configure()` — silently no-ops
- Don't remove `ak_` prefixed UserDefaults keys — breaks attribution state
- ASA token is single-use per Apple docs — don't retry the same token value
