//
//  RevenueIntegration.swift
//  AttributionKit / Examples
//
//  Reference integration showing how install attribution and subscription
//  revenue get joined on the Attribution server. The join key is IDFV:
//
//    Attribution.idfv  ←  AttributionKit auto-collects this
//                       ↕  (server-side join at webhook insert time)
//    Revenue.external_user_id  ←  must equal IDFV for the join to succeed
//
//  This example uses Qonversion as the revenue provider. For the Adapty
//  variant, see the commented block at the bottom of this file. Do NOT
//  run both providers concurrently — every transaction will be counted twice.
//
//  Usage: call `AttributionBootstrap.setup()` once at app launch, before
//  any purchase or paywall flow runs.
//

import Foundation
import UIKit
import AttributionKit
import Qonversion

enum AttributionBootstrap {

    // MARK: - Public entry point

    /// Single entry point. Call from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
    /// or your `@main App` initializer.
    static func setup() {
        configureAttributionKit()
        configureQonversion()
    }

    /// Wire from SwiftUI `.onOpenURL` or `AppDelegate.application(_:continue:restorationHandler:)`
    /// to capture UTM params from Universal Links.
    static func handleIncomingURL(_ url: URL) {
        AttributionKit.shared.handleUniversalLink(url)
    }

    // MARK: - AttributionKit

    private static func configureAttributionKit() {
        AttributionKit.shared.configure(
            apiKey:  "<product api_key from server /admin>",
            appId:   "<product app_id from server /admin>",
            baseURL: "https://attribution.your-domain.com"

            // Optional: bridge an analytics distinct_id (e.g. PostHog) for
            // server-side identify. Leave nil if you only have IDFV.
            // distinctIdProvider: { PostHogSDK.shared.getDistinctId() }
        )
        AttributionKit.shared.performAttributionIfNeeded()
    }

    // MARK: - Qonversion (chosen revenue provider)

    private static func configureQonversion() {
        let config = Qonversion.Configuration(
            projectKey: "<your-qonversion-project-key>",
            launchMode: .subscriptionManagement
        )
        Qonversion.initWithConfig(config)

        // ───────────────────────────────────────────────────────────────
        // CRITICAL: align Qonversion's customUserId with AttributionKit's
        // idfv. Without this, every Revenue document the server inserts
        // is tagged attribution_source = 'unknown' and LTV-by-source
        // queries return nothing.
        //
        // setUserProperty(.userID, …) is Qonversion v3's documented API
        // for setting custom_user_id; the value is forwarded into
        // webhook payloads as `body.custom_user_id`, which the server's
        // normalizer reads at routes/v1/webhook/qonversion.js.
        // ───────────────────────────────────────────────────────────────
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            Qonversion.shared().setUserProperty(.userID, value: idfv)
        }

        // (Optional) Forward ASA token to Qonversion as well. Safe even
        // when AttributionKit independently collects ASA — the two paths
        // do not interfere.
        Qonversion.shared().collectAppleSearchAdsAttribution()
    }
}

// =============================================================================
// Adapty alternative
// =============================================================================
//
// Replace `configureQonversion()` above with this. Server-side, set
// ADAPTY_WEBHOOK_SECRET in env and configure the dashboard webhook at
//   POST https://attribution.your-domain.com/v1/webhook/adapty/<appId>
// with `Authorization: <secret>` (raw value, no `Basic ` prefix).
//
// import Adapty
//
// private static func configureAdapty() async {
//     try? await Adapty.activate("<your-adapty-public-sdk-key>")
//
//     // Same join-key requirement as Qonversion: customer_user_id == IDFV.
//     if let idfv = UIDevice.current.identifierForVendor?.uuidString {
//         try? await Adapty.identify(idfv)
//     }
// }
//
// =============================================================================
