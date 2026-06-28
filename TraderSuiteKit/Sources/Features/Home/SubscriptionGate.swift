import SwiftUI

/// Free-tier caps for non-subscribers.
enum SubscriptionLimit {
    static let depositsPerExchange = 1
    static let watchlist = 3
}

/// Overlays a crown badge and intercepts taps with the paywall when `isBlocked`
/// is true. When false the modifier is a no-op.
struct ProGateModifier: ViewModifier {
    let isBlocked: Bool
    var badgeAlignment: Alignment = .topTrailing
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        content
//            .overlay(alignment: .topTrailing) {
//                if isBlocked {
//                    Image(systemName: "crown.fill")
//                        .font(.system(size: 8, weight: .bold))
//                        .foregroundStyle(.yellow)
//                        .padding(3)
//                        .background(.white, in: Circle())
//                }
//            }
            // While gated, stop the wrapped control from receiving the tap so its
            // own action can't fire alongside the paywall button below. Otherwise a
            // single tap triggers both, and when the wrapped action also presents a
            // sheet (e.g. the notification setup), two presentations race — SwiftUI
            // logs "...already presenting..." and one is immediately dismissed.
            // `allowsHitTesting` (not `disabled`) keeps the control's normal look.
            .allowsHitTesting(!isBlocked)
            .overlay {
                if isBlocked {
                    Button { showPaywall = true } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                }
            }
            .sheet(isPresented: $showPaywall) { SubscriptionView() }
    }
}

extension View {
    /// Intercepts taps and presents the subscription paywall when `isBlocked` is true.
    /// - Parameter badgeAlignment: Where to place the crown badge. Default: `.topTrailing`.
    func proGated(_ isBlocked: Bool, badgeAlignment: Alignment = .topTrailing) -> some View {
        modifier(ProGateModifier(isBlocked: isBlocked, badgeAlignment: badgeAlignment))
    }
}
