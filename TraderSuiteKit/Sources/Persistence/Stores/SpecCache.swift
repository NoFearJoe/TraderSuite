import Foundation
import SwiftData
import Core

/// On-device cache of contract specifications fetched from an exchange adapter.
///
/// Specs (margin, step price, fees) change slowly — caching avoids a network
/// round-trip on every calculation and lets the app work offline against the
/// last-known values. Entries carry an `updatedAt` stamp so callers can decide
/// when a refresh is due (see `defaultMaxAge`).
@MainActor
public struct SpecCache {
    /// How long a cached spec is considered fresh by default (6 hours).
    /// FORTS margin/fee figures are revised at most daily.
    public static let defaultMaxAge: TimeInterval = 6 * 60 * 60

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// The raw cached entity for a symbol, regardless of age.
    public func entity(symbol: String, exchangeIDRaw: String) throws -> CachedSpecEntity? {
        var descriptor = FetchDescriptor<CachedSpecEntity>(
            predicate: #Predicate {
                $0.exchangeIDRaw == exchangeIDRaw && $0.symbol == symbol
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// A cached spec value, but only if it is still fresh.
    /// Returns `nil` when there is no entry or it is older than `maxAge`,
    /// signalling the caller to refetch from the exchange.
    public func freshSpec(
        symbol: String,
        exchangeIDRaw: String,
        maxAge: TimeInterval = defaultMaxAge,
        now: Date = .now
    ) throws -> ContractSpec? {
        guard let entity = try entity(symbol: symbol, exchangeIDRaw: exchangeIDRaw) else {
            return nil
        }
        guard now.timeIntervalSince(entity.updatedAt) <= maxAge else { return nil }
        return entity.asContractSpec()
    }

    /// Insert or refresh the cached spec for a symbol, stamping `updatedAt`.
    @discardableResult
    public func upsert(
        _ spec: ContractSpec,
        exchangeIDRaw: String,
        isPerpetual: Bool = false,
        expiration: Date? = nil,
        now: Date = .now
    ) throws -> CachedSpecEntity {
        if let existing = try entity(symbol: spec.symbol, exchangeIDRaw: exchangeIDRaw) {
            existing.minStep = spec.minStep
            existing.stepPrice = spec.stepPrice
            existing.initialMargin = spec.initialMargin
            existing.exchangeFeePerSide = spec.exchangeFeePerSide
            existing.isPerpetual = isPerpetual
            existing.expiration = expiration
            existing.updatedAt = now
            try context.save()
            return existing
        }
        let entity = CachedSpecEntity(
            symbol: spec.symbol,
            exchangeIDRaw: exchangeIDRaw,
            minStep: spec.minStep,
            stepPrice: spec.stepPrice,
            initialMargin: spec.initialMargin,
            exchangeFeePerSide: spec.exchangeFeePerSide,
            isPerpetual: isPerpetual,
            expiration: expiration,
            updatedAt: now
        )
        context.insert(entity)
        try context.save()
        return entity
    }

    /// Drop cache entries older than `maxAge`. Returns the number removed.
    @discardableResult
    public func purgeStale(
        maxAge: TimeInterval = defaultMaxAge,
        now: Date = .now
    ) throws -> Int {
        let all = try context.fetch(FetchDescriptor<CachedSpecEntity>())
        let stale = all.filter { now.timeIntervalSince($0.updatedAt) > maxAge }
        for entity in stale { context.delete(entity) }
        if !stale.isEmpty { try context.save() }
        return stale.count
    }
}
