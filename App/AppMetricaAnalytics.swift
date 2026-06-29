import Foundation
import Features

#if canImport(AppMetricaCore)
import AppMetricaCore

/// Concrete `AnalyticsReporting` backed by AppMetrica. Lives in the app target so
/// the `Features` package stays SDK-free (and keeps compiling on macOS / in
/// `swift test`). Event and parameter names come from the `Features` catalog
/// (`AnalyticsEvents.swift`); this type only forwards them to the SDK.
struct AppMetricaAnalytics: AnalyticsReporting {
    func report(_ event: String, parameters: [String: String]) {
        // AppMetrica's reporting queue is thread-safe; nil parameters for an
        // event with none keeps the dashboard tidy.
        AppMetrica.reportEvent(name: event, parameters: parameters.isEmpty ? nil : parameters) { _ in }
    }
}

enum AppMetricaSetup {
    /// AppMetrica application key for TraderSuite.
    static let apiKey = "3e0ef794-b73d-44d7-939d-6581d991092c"

    /// Activate the SDK once, at launch. Safe to call before any `reportEvent`.
    static func activate() {
        guard let configuration = AppMetricaConfiguration(apiKey: apiKey) else { return }
        AppMetrica.activate(with: configuration)
    }

    /// The live reporter to inject into `AppEnvironment`.
    static func makeReporter() -> AnalyticsReporting { AppMetricaAnalytics() }
}

#else

// AppMetrica is iOS/tvOS-only. On platforms without the SDK (macOS), analytics
// is a no-op so the rest of the app builds and runs unchanged.
enum AppMetricaSetup {
    static func activate() {}
    static func makeReporter() -> AnalyticsReporting { NoopAnalytics() }
}

#endif
