import SwiftUI

/// Free-tier caps for non-subscribers.
enum SubscriptionLimit {
    static let depositsPerExchange = 1
    static let watchlist = 3
}

/// Intercepts taps with the paywall when `isBlocked` is true. When false the
/// modifier is a no-op.
struct ProGateModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    let isBlocked: Bool
    /// Which free-tier cap this gate guards — reported on `paywall_blocked`.
    let feature: AnalyticsFeature
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
            // While gated, stop the wrapped control from receiving the tap so its
            // own action can't fire alongside the paywall button below. Otherwise a
            // single tap triggers both, and when the wrapped action also presents a
            // sheet (e.g. the notification setup), two presentations race — SwiftUI
            // logs "...already presenting..." and one is immediately dismissed.
            // `allowsHitTesting` (not `disabled`) keeps the control's normal look.
            .allowsHitTesting(!isBlocked)
            .overlay {
                if isBlocked {
                    Button {
                        env.analytics.log(.paywallBlocked, [.feature: feature.rawValue])
                        showPaywall = true
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                SubscriptionView()
                    .onAppear { env.analytics.log(.paywallShown, [.source: AnalyticsSource.proGate.rawValue]) }
            }
    }
}

extension View {
    /// Intercepts taps and presents the subscription paywall when `isBlocked` is true.
    /// - Parameter feature: the free-tier cap being guarded, for `paywall_blocked` analytics.
    func proGated(_ isBlocked: Bool, feature: AnalyticsFeature) -> some View {
        modifier(ProGateModifier(isBlocked: isBlocked, feature: feature))
    }
}
