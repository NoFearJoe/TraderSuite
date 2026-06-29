import Foundation

// MARK: - Analytics catalog
//
// Single source of truth for every analytics event name, parameter key and
// screen identifier sent to AppMetrica. Keep ALL names here so they can be
// reviewed in one place and reused across screens without typos. The concrete
// reporter (AppMetrica) lives in the app target; `Features` only knows these
// names and the `AnalyticsReporting` seam (see Analytics.swift).
//
// Naming convention: snake_case, lowercase. Event names read as
// "<noun>_<verb-past>" where it helps a funnel (e.g. `instrument_added`).

/// A user-facing screen, reported via the `screen_view` event.
public enum AnalyticsScreen: String {
    case home
    case instrumentInfo = "instrument_info"
    case lotCalc = "lot_calc"
    case averaging
    case deposits
    case settings
    case paywall
    case onboarding
    case notificationSetup = "notification_setup"
}

/// Every analytics event the app reports.
public enum AnalyticsEvent: String {
    /// A screen was shown. Carries `.screen`.
    case screenView = "screen_view"

    // Onboarding
    case onboardingCompleted = "onboarding_completed"

    // Watchlist / instruments
    case exchangeSelected = "exchange_selected"     // .exchange
    case instrumentAdded = "instrument_added"       // .exchange .family .symbol .source
    case instrumentRemoved = "instrument_removed"   // .exchange .symbol
    case watchlistReordered = "watchlist_reordered" // .exchange
    case contractRolledOver = "contract_rolled_over" // .exchange .count

    // Calculators
    case riskSelected = "risk_selected"             // .screen .exchange .riskPercent .isPreset
    case positionCalculated = "position_calculated" // .exchange .symbol .riskPercent .lots .limitedByMargin
    case averagingCalculated = "averaging_calculated" // .exchange .symbol .lots

    // Deposits
    case depositSelected = "deposit_selected"       // .exchange
    case depositCreated = "deposit_created"         // .exchange
    case depositDeleted = "deposit_deleted"         // .exchange

    // Notifications
    case notificationConfigured = "notification_configured" // .exchange .enabled .leadDays

    // Subscription / paywall
    case paywallShown = "paywall_shown"             // .source
    case paywallBlocked = "paywall_blocked"         // .feature  (a free-tier cap was hit)
    case subscriptionActivated = "subscription_activated"

    // Settings actions
    case appShared = "app_shared"
    case appRated = "app_rated"
    case supportContacted = "support_contacted"
}

/// Every parameter key attached to an event. Values are sent as strings.
public enum AnalyticsProperty: String {
    case screen
    case exchange
    case family
    case symbol
    case source
    case riskPercent = "risk_percent"
    case isPreset = "is_preset"
    case lots
    case limitedByMargin = "limited_by_margin"
    case enabled
    case leadDays = "lead_days"
    case feature
    case count
}

/// Stable values for the `.source` parameter, so funnels group cleanly.
public enum AnalyticsSource: String {
    case search
    case instrumentInfo = "instrument_info"
    case settings
    case proGate = "pro_gate"
    case notificationRow = "notification_row"
}

/// Stable values for the `.feature` parameter on `paywall_blocked`.
public enum AnalyticsFeature: String {
    case watchlist
    case deposits
}
