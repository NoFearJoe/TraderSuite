import Foundation
import SwiftData

/// CRUD access to trading deposits, backed by a SwiftData `ModelContext`.
///
/// `@MainActor` because `ModelContext` is not `Sendable`; view models on the
/// main actor own and drive the store. Exchange identity crosses the API as a
/// raw string (`ExchangeID.rawValue`) — `Persistence` does not depend on
/// `ExchangeKit`, so callers in `Features` do the bridging.
@MainActor
public struct DepositStore {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// All deposits, newest first.
    public func all() throws -> [DepositEntity] {
        try context.fetch(
            FetchDescriptor<DepositEntity>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    /// Deposits belonging to one exchange, newest first.
    public func deposits(forExchange exchangeIDRaw: String) throws -> [DepositEntity] {
        let descriptor = FetchDescriptor<DepositEntity>(
            predicate: #Predicate { $0.exchangeIDRaw == exchangeIDRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Insert a new deposit and persist it.
    @discardableResult
    public func add(
        name: String,
        exchangeIDRaw: String,
        balance: Decimal,
        currencyCode: String,
        riskPercent: Decimal,
        now: Date = .now
    ) throws -> DepositEntity {
        let deposit = DepositEntity(
            name: name,
            exchangeIDRaw: exchangeIDRaw,
            balance: balance,
            currencyCode: currencyCode,
            riskPercent: riskPercent,
            createdAt: now
        )
        context.insert(deposit)
        try context.save()
        return deposit
    }

    /// Persist edits made to an already-inserted deposit.
    public func save() throws {
        try context.save()
    }

    public func delete(_ deposit: DepositEntity) throws {
        context.delete(deposit)
        try context.save()
    }
}
