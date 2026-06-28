import Foundation
import SwiftData

/// CRUD access to watchlist. A watchlist tracks an instrument *family* and the
/// currently active front contract, so it survives rollovers after expiration
/// (the active symbol is updated, the watchlist stays).
@MainActor
public struct WatchlistStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Sort by the user's explicit order, then newest first as a tiebreaker.
    private static let order: [SortDescriptor<WatchlistEntity>] = [
        SortDescriptor(\.sortOrder, order: .forward),
        SortDescriptor(\.createdAt, order: .reverse),
    ]

    /// All watchlist, in user order (newest first within an equal order).
    public func all() throws -> [WatchlistEntity] {
        try context.fetch(FetchDescriptor<WatchlistEntity>(sortBy: Self.order))
    }

    /// Watchlist belonging to one exchange, in user order.
    public func watchlist(forExchange exchangeIDRaw: String) throws -> [WatchlistEntity] {
        let descriptor = FetchDescriptor<WatchlistEntity>(
            predicate: #Predicate { $0.exchangeIDRaw == exchangeIDRaw },
            sortBy: Self.order
        )
        return try context.fetch(descriptor)
    }

    /// The watchlist tracking a family on an exchange, if any (first match).
    public func watchlist(family: String, exchangeIDRaw: String) throws -> WatchlistEntity? {
        var descriptor = FetchDescriptor<WatchlistEntity>(
            predicate: #Predicate {
                $0.exchangeIDRaw == exchangeIDRaw && $0.family == family
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The watchlist tracking a specific contract on an exchange, if any.
    public func watchlist(symbol: String, exchangeIDRaw: String) throws -> WatchlistEntity? {
        var descriptor = FetchDescriptor<WatchlistEntity>(
            predicate: #Predicate {
                $0.exchangeIDRaw == exchangeIDRaw && $0.activeSymbol == symbol
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Add a watchlist entry for a specific contract, or return the existing one.
    /// De-duplication is per *contract* (symbol), so different contracts of the
    /// same family coexist (e.g. Si-6.26 and Si-9.26). Done here rather than with a
    /// `.unique` constraint, which would break CloudKit-safety.
    @discardableResult
    public func add(
        exchangeIDRaw: String,
        family: String,
        activeSymbol: String,
        displayName: String? = nil,
        activeExpiration: Date? = nil,
        iconURLString: String? = nil,
        now: Date = .now
    ) throws -> WatchlistEntity {
        if let existing = try watchlist(symbol: activeSymbol, exchangeIDRaw: exchangeIDRaw) {
            existing.activeExpiration = activeExpiration
            existing.iconURLString = iconURLString
            try context.save()
            return existing
        }
        let watchlist = WatchlistEntity(
            exchangeIDRaw: exchangeIDRaw,
            family: family,
            activeSymbol: activeSymbol,
            displayName: displayName ?? family,
            activeExpiration: activeExpiration,
            iconURLString: iconURLString,
            createdAt: now
        )
        context.insert(watchlist)
        try context.save()
        return watchlist
    }

    /// Roll a watchlist forward to a new front contract after expiration.
    public func roll(
        _ watchlist: WatchlistEntity,
        to activeSymbol: String,
        expiration: Date? = nil,
        iconURLString: String? = nil
    ) throws {
        watchlist.activeSymbol = activeSymbol
        watchlist.activeExpiration = expiration
        watchlist.iconURLString = iconURLString
        try context.save()
    }

    /// Persist an explicit ordering after a drag-to-reorder: each entry's
    /// `sortOrder` is set to its index in `ordered`. Pass the entries for a single
    /// exchange (the reordered list); other exchanges are untouched.
    public func reorder(_ ordered: [WatchlistEntity]) throws {
        for (index, entity) in ordered.enumerated() {
            entity.sortOrder = index
        }
        try context.save()
    }

    /// Persist notification preference changes for a tracked watchlist.
    public func saveNotification(for watchlist: WatchlistEntity, enabled: Bool, leadDays: Int) throws {
        watchlist.notificationEnabled = enabled
        watchlist.notificationLeadDays = max(0, min(7, leadDays))
        try context.save()
    }

    public func delete(_ watchlist: WatchlistEntity) throws {
        context.delete(watchlist)
        try context.save()
    }
}
