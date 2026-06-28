import Foundation
import Core
import ExchangeKit
import Persistence

/// Bridges the on-device `SpecCache` (Persistence) with live exchange adapters
/// (ExchangeKit). This is the seam where watchlist/deposits meet real market
/// data: callers ask for a contract spec and get a cached value when fresh,
/// a network fetch when not, and the last-known cached value when offline.
///
/// `@MainActor` because it drives `SpecCache`, which owns a `ModelContext`.
@MainActor
public final class SpecProvider {
    public enum ProviderError: Error, Equatable {
        /// No adapter is registered for the requested exchange.
        case noAdapter(ExchangeID)
        /// The network fetch failed and no cached value exists to fall back on.
        case unavailable(symbol: String, underlying: String)
    }

    private let cache: SpecCache
    private let registry: ExchangeRegistry

    public init(cache: SpecCache, registry: ExchangeRegistry) {
        self.cache = cache
        self.registry = registry
    }

    /// A contract spec, cache-first.
    ///
    /// 1. Fresh cache entry (within `maxAge`) → returned without a network call.
    /// 2. Otherwise fetch from the exchange adapter, cache it, and return it.
    /// 3. If the fetch fails but a (possibly stale) cache entry exists, return
    ///    that so the app keeps working offline. Only with no entry at all does
    ///    this throw.
    public func spec(
        symbol: String,
        exchange: ExchangeID,
        maxAge: TimeInterval = SpecCache.defaultMaxAge,
        now: Date = .now
    ) async throws -> ContractSpec {
        let exchangeIDRaw = exchange.rawValue

        if let fresh = try cache.freshSpec(
            symbol: symbol, exchangeIDRaw: exchangeIDRaw, maxAge: maxAge, now: now
        ) {
            return fresh
        }

        guard let adapter = await registry.adapter(for: exchange) else {
            // No adapter — fall back to any cached value before giving up.
            if let stale = try cache.entity(symbol: symbol, exchangeIDRaw: exchangeIDRaw) {
                return stale.asContractSpec()
            }
            throw ProviderError.noAdapter(exchange)
        }

        do {
            let spec = try await adapter.fetchSpec(symbol: symbol)
            try cache.upsert(spec, exchangeIDRaw: exchangeIDRaw, now: now)
            return spec
        } catch {
            if let stale = try cache.entity(symbol: symbol, exchangeIDRaw: exchangeIDRaw) {
                return stale.asContractSpec()  // offline fallback
            }
            throw ProviderError.unavailable(
                symbol: symbol, underlying: String(describing: error)
            )
        }
    }

    /// Force a refresh from the exchange, bypassing cache freshness, and update
    /// the cache. Use for pull-to-refresh. Still falls back to a cached value if
    /// the network is unavailable.
    public func refreshSpec(
        symbol: String,
        exchange: ExchangeID,
        now: Date = .now
    ) async throws -> ContractSpec {
        try await spec(symbol: symbol, exchange: exchange, maxAge: 0, now: now)
    }
}
