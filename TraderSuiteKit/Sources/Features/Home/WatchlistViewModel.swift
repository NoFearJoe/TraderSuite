import Foundation
import Observation
import Core
import ExchangeKit
import Persistence

/// Drives the watchlist screen: tracks instrument *families*, resolves their
/// current front contract from the exchange, surfaces expiration status, and
/// rolls expired contracts forward. SwiftUI-free for unit testing.
@MainActor
@Observable
public final class WatchlistViewModel {
    private let store: WatchlistStore
    private let registry: ExchangeRegistry
    private let scheduler: NotificationScheduling?

    public private(set) var watchlist: [WatchlistEntity] = []
    public var errorMessage: String?
    public private(set) var isWorking = false

    /// Instruments matching the current search query (for adding to watchlist).
    public private(set) var searchResults: [InstrumentSummary] = []
    /// True while the instrument list for an exchange is being fetched.
    public private(set) var isSearching = false
    /// Cached instrument lists per exchange so typing doesn't refetch each keystroke.
    private var instrumentCache: [ExchangeID: [InstrumentSummary]] = [:]

    public init(
        store: WatchlistStore,
        registry: ExchangeRegistry,
        scheduler: NotificationScheduling? = nil
    ) {
        self.store = store
        self.registry = registry
        self.scheduler = scheduler
        reload()
    }

    /// Ask for notification permission (no-op without a scheduler).
    @discardableResult
    public func requestNotificationAuthorization() async -> Bool {
        await scheduler?.requestAuthorization() ?? false
    }

    /// Current notification permission, without prompting (no-op without a scheduler).
    public func notificationAuthorizationStatus() async -> NotificationAuthorization {
        await scheduler?.authorizationStatus() ?? .notDetermined
    }

    /// Rebuild expiration reminders from the current watchlist, respecting
    /// per-instrument notification preferences.
    public func syncReminders(now: Date = Date()) async {
        guard let scheduler else { return }
        var reminders: [ExpirationNotification] = []
        for watchlist in watchlist {
            guard watchlist.notificationEnabled,
                  let expiration = watchlist.activeExpiration else { continue }
            let expiry = WatchlistExpiry(
                family: watchlist.family,
                symbol: watchlist.activeSymbol,
                expiration: expiration
            )
            reminders += ExpirationNotificationBuilder.build(
                for: [expiry], now: now, leadDays: [watchlist.notificationLeadDays]
            )
        }
        await scheduler.replaceExpirationReminders(reminders)
    }

    /// Save notification preference for a watchlist and reschedule all reminders.
    public func setNotification(for watchlist: WatchlistEntity, enabled: Bool, leadDays: Int, now: Date = Date()) async {
        do {
            try store.saveNotification(for: watchlist, enabled: enabled, leadDays: leadDays)
            reload()
            await syncReminders(now: now)
        } catch {
            errorMessage = String(localized: "error_save_notification")
        }
    }

    public func reload() {
        do {
            watchlist = try store.all()
        } catch {
            errorMessage = String(localized: "error_load_watchlist")
        }
    }

    public func status(for watchlist: WatchlistEntity, now: Date = Date()) -> ExpirationStatus {
        ExpirationPolicy.status(expiration: watchlist.activeExpiration, now: now)
    }

    /// Filter the exchange's instruments by a free-text query (symbol, family or
    /// display name). Empty query clears the results. Instruments are fetched once
    /// per exchange and cached.
    public func search(_ rawQuery: String, exchange: ExchangeID) async {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        let all = await instruments(for: exchange)
        searchResults = all
            .filter {
                $0.symbol.lowercased().contains(query)
                    || $0.family.lowercased().contains(query)
                    || $0.displayName.lowercased().contains(query)
            }
            .sorted(by: Self.byExpirationAscending)
    }

    /// Order instruments by nearest expiration first; perpetual (no expiration)
    /// contracts sink to the bottom, ties broken by symbol for stable ordering.
    private static func byExpirationAscending(_ lhs: InstrumentSummary, _ rhs: InstrumentSummary) -> Bool {
        switch (lhs.expiration, rhs.expiration) {
        case let (l?, r?): return l == r ? lhs.symbol < rhs.symbol : l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.symbol < rhs.symbol
        }
    }

    /// Add a watchlist straight from a search result (tracks its family).
    @discardableResult
    public func addWatchlist(summary: InstrumentSummary, exchange: ExchangeID, now: Date = Date()) async -> Bool {
        await addWatchlist(family: summary.family, displayName: summary.displayName, exchange: exchange, now: now)
    }

    /// Add a specific contract picked from search: stores it as the family's
    /// active contract directly, without re-resolving the front (we already have
    /// the symbol + expiration). Subsequent expiration roll-over still applies.
    @discardableResult
    public func addWatchlist(contract: InstrumentSummary, exchange: ExchangeID, now: Date = Date()) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try store.add(
                exchangeIDRaw: exchange.rawValue,
                family: contract.family,
                activeSymbol: contract.symbol,
                displayName: contract.displayName,
                activeExpiration: contract.expiration,
                iconURLString: contract.iconURL?.absoluteString
            )
            errorMessage = nil
            reload()
            await syncReminders(now: now)
            return true
        } catch {
            errorMessage = String(localized: "error_add_contract")
            return false
        }
    }

    /// Whether a specific contract is already tracked on an exchange.
    public func isWatchlist(symbol: String, exchange: ExchangeID) -> Bool {
        watchlist.contains { $0.activeSymbol == symbol && $0.exchangeIDRaw == exchange.rawValue }
    }

    /// Number of tracked instruments on a given exchange. The free-tier watchlist
    /// limit applies per exchange, so gating counts entries scoped to one exchange.
    public func count(for exchange: ExchangeID) -> Int {
        watchlist.reduce(0) { $0 + ($1.exchangeIDRaw == exchange.rawValue ? 1 : 0) }
    }

    private func instruments(for exchange: ExchangeID) async -> [InstrumentSummary] {
        if let cached = instrumentCache[exchange] { return cached }
        guard let adapter = await registry.adapter(for: exchange) else { return [] }
        isSearching = true
        defer { isSearching = false }
        do {
            let list = try await adapter.fetchInstruments()
            instrumentCache[exchange] = list
            return list
        } catch {
            errorMessage = String(localized: "error_load_instruments")
            return []
        }
    }

    /// Track a new family: resolve its current front contract and store it.
    /// `displayName` defaults to the family code when not supplied.
    @discardableResult
    public func addWatchlist(family: String, displayName: String? = nil, exchange: ExchangeID, now: Date = Date()) async -> Bool {
        let trimmed = family.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "error_empty_instrument_code")
            return false
        }
        guard let adapter = await registry.adapter(for: exchange) else {
            errorMessage = String(localized: "error_exchange_unavailable")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let front = try await adapter.frontInstrument(family: trimmed, now: now)
            try store.add(
                exchangeIDRaw: exchange.rawValue,
                family: trimmed,
                activeSymbol: front.symbol,
                displayName: displayName ?? trimmed,
                activeExpiration: front.expiration,
                iconURLString: front.iconURL?.absoluteString
            )
            errorMessage = nil
            reload()
            await syncReminders(now: now)
            return true
        } catch ExchangeError.instrumentNotFound {
            errorMessage = String(format: String(localized: "error_contract_not_found"), trimmed)
            return false
        } catch {
            errorMessage = String(localized: "error_load_contract")
            return false
        }
    }

    /// Roll one watchlist to the current front contract.
    @discardableResult
    public func roll(_ watchlist: WatchlistEntity, now: Date = Date()) async -> Bool {
        guard let exchange = ExchangeID(rawValue: watchlist.exchangeIDRaw),
              let adapter = await registry.adapter(for: exchange) else {
            errorMessage = String(localized: "error_exchange_unavailable")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let front = try await adapter.frontInstrument(family: watchlist.family, now: now)
            // Contracts are tracked individually, so the front this entry would roll
            // into may already be tracked by another entry. Rolling onto it would
            // duplicate the contract — drop the expired entry instead.
            let alreadyTracked = front.symbol != watchlist.activeSymbol && self.watchlist.contains {
                $0 !== watchlist
                    && $0.exchangeIDRaw == watchlist.exchangeIDRaw
                    && $0.activeSymbol == front.symbol
            }
            if alreadyTracked {
                try store.delete(watchlist)
            } else {
                try store.roll(
                    watchlist,
                    to: front.symbol,
                    expiration: front.expiration,
                    iconURLString: front.iconURL?.absoluteString
                )
            }
            errorMessage = nil
            reload()
            await syncReminders(now: now)
            return true
        } catch {
            errorMessage = String(localized: "error_update_contract")
            return false
        }
    }

    /// Auto-rollover: roll every watchlist whose active contract has expired.
    /// Returns the number rolled. Per-watchlist failures are skipped silently so
    /// one bad family doesn't block the rest.
    @discardableResult
    public func rolloverExpired(now: Date = Date()) async -> Int {
        var rolled = 0
        for watchlist in watchlist where status(for: watchlist, now: now) == .expired {
            if await roll(watchlist, now: now) { rolled += 1 }
        }
        return rolled
    }

    /// Remove the watchlist entry tracking a specific contract on an exchange, if
    /// present. Lets callers drop an entry by value without holding the reference.
    public func removeWatchlist(symbol: String, exchange: ExchangeID) {
        if let watchlist = watchlist.first(where: {
            $0.activeSymbol == symbol && $0.exchangeIDRaw == exchange.rawValue
        }) {
            remove(watchlist)
        }
    }

    public func remove(_ watchlist: WatchlistEntity) {
        do {
            try store.delete(watchlist)
            reload()
        } catch {
            errorMessage = String(localized: "error_remove_watchlist")
        }
    }

    public func remove(at offsets: IndexSet) {
        for index in offsets where watchlist.indices.contains(index) {
            remove(watchlist[index])
        }
    }

    /// Reorder a displayed (per-exchange) slice of the watchlist after a drag.
    /// `displayed` is the exact array shown in the list; `source`/`destination`
    /// are the `onMove` offsets into it. The new order is persisted and reloaded.
    public func move(_ displayed: [WatchlistEntity], from source: IndexSet, to destination: Int) {
        var reordered = displayed
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            try store.reorder(reordered)
            reload()
        } catch {
            errorMessage = String(localized: "error_reorder_watchlist")
        }
    }
}
