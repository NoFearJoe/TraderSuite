import Foundation
import SwiftData

/// Persists per-instrument calculator drafts so a screen can pre-fill the user's
/// previous inputs. De-duplicated on (exchange, symbol, kind) — one draft each.
///
/// `@MainActor` because `ModelContext` is not `Sendable`. The `payload` is an
/// opaque blob whose shape the `Features` layer owns; this store never decodes it.
@MainActor
public struct CalcDraftStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// The saved draft for an instrument's calculator, if any.
    public func draft(exchangeIDRaw: String, symbol: String, kindRaw: String) throws -> CalcDraftEntity? {
        var descriptor = FetchDescriptor<CalcDraftEntity>(
            predicate: #Predicate {
                $0.exchangeIDRaw == exchangeIDRaw && $0.symbol == symbol && $0.kindRaw == kindRaw
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Insert or update the draft for an instrument's calculator.
    public func save(
        exchangeIDRaw: String,
        symbol: String,
        kindRaw: String,
        payload: Data,
        now: Date = .now
    ) throws {
        if let existing = try draft(exchangeIDRaw: exchangeIDRaw, symbol: symbol, kindRaw: kindRaw) {
            existing.payload = payload
            existing.updatedAt = now
        } else {
            context.insert(CalcDraftEntity(
                exchangeIDRaw: exchangeIDRaw,
                symbol: symbol,
                kindRaw: kindRaw,
                payload: payload,
                updatedAt: now
            ))
        }
        try context.save()
    }

    /// Drop the draft for an instrument's calculator, if present.
    public func delete(exchangeIDRaw: String, symbol: String, kindRaw: String) throws {
        if let existing = try draft(exchangeIDRaw: exchangeIDRaw, symbol: symbol, kindRaw: kindRaw) {
            context.delete(existing)
            try context.save()
        }
    }
}
