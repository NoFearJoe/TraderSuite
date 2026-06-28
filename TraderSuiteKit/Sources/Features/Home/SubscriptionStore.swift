import Foundation
import Observation
import StoreKit

/// Tracks the user's real subscription entitlement via StoreKit 2. Reads the
/// current entitlements on start and listens to `Transaction.updates` so the
/// status reflects purchases, renewals, expirations and revocations live.
@MainActor
@Observable
public final class SubscriptionStore {
    /// The Premium auto-renewable subscription product.
    public static let premiumProductID = "com.mesterra.tradersuite.pro"

    /// Whether the user currently has an active Premium entitlement.
    public private(set) var isSubscribed = false

    @ObservationIgnored private nonisolated(unsafe) var updatesTask: Task<Void, Never>?

    public init() {}

    /// Refresh from current entitlements and start listening for changes (idempotent).
    public func start() async {
        await refresh()
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refresh()
            }
        }
    }

    /// Recompute `isSubscribed` from the current StoreKit entitlements.
    public func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.premiumProductID, transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    deinit { updatesTask?.cancel() }
}
