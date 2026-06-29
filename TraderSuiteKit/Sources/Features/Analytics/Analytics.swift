import Foundation
import SwiftUI

/// Seam over the analytics backend (AppMetrica) so screens and view models can
/// report usage without depending on the SDK. `Features` stays SDK-free and
/// testable; the real reporter is injected by the app target. Previews and tests
/// use `NoopAnalytics`.
///
/// Reporting is fire-and-forget: callers never await or handle failures.
public protocol AnalyticsReporting: Sendable {
    /// Report a named event with optional string parameters. Prefer the typed
    /// `log(_:_:)` / `screen(_:)` helpers below over calling this directly.
    func report(_ event: String, parameters: [String: String])
}

public extension AnalyticsReporting {
    /// Report a catalog event with typed parameters.
    func log(_ event: AnalyticsEvent, _ parameters: [AnalyticsProperty: String] = [:]) {
        var raw: [String: String] = [:]
        for (key, value) in parameters { raw[key.rawValue] = value }
        report(event.rawValue, parameters: raw)
    }

    /// Report that a screen was shown.
    func screen(_ screen: AnalyticsScreen) {
        report(AnalyticsEvent.screenView.rawValue, parameters: [AnalyticsProperty.screen.rawValue: screen.rawValue])
    }
}

/// No-op reporter for previews, tests and platforms without the SDK (macOS).
public struct NoopAnalytics: AnalyticsReporting {
    public init() {}
    public func report(_ event: String, parameters: [String: String]) {}
}

// MARK: - Screen tracking

/// Reports a `screen_view` each time the view appears. Attach with `.trackScreen(_:)`.
private struct ScreenTrackingModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    let screen: AnalyticsScreen

    func body(content: Content) -> some View {
        content.onAppear { env.analytics.screen(screen) }
    }
}

public extension View {
    /// Report a `screen_view` for `screen` whenever this view appears.
    func trackScreen(_ screen: AnalyticsScreen) -> some View {
        modifier(ScreenTrackingModifier(screen: screen))
    }
}
