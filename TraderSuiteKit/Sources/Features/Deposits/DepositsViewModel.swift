import Foundation
import Observation
import Core
import ExchangeKit
import Persistence

/// Drives the deposit-management screen over a `DepositStore`. Pure of SwiftUI
/// so it can be unit-tested with an in-memory store.
@MainActor
@Observable
public final class DepositsViewModel {
    private let store: DepositStore
    private let exchangeFilter: ExchangeID?

    public private(set) var deposits: [DepositEntity] = []
    public var errorMessage: String?

    /// - Parameter exchangeFilter: When set, only deposits for this exchange are loaded.
    ///   Pass `nil` (default) to load all deposits — useful for management screens.
    public init(store: DepositStore, exchangeFilter: ExchangeID? = nil) {
        self.store = store
        self.exchangeFilter = exchangeFilter
        reload()
    }

    public func reload() {
        do {
            deposits = try exchangeFilter.map { try store.deposits(forExchange: $0.rawValue) }
                ?? store.all()
        } catch {
            errorMessage = String(localized: "error_load_deposits")
        }
    }

    /// Validate and create a deposit. Returns the new entity, or nil on invalid
    /// input (with `errorMessage` set). `riskPercentText` is a whole percent.
    @discardableResult
    public func addDeposit(
        name: String,
        exchange: ExchangeID,
        balanceText: String,
        riskPercentText: String
    ) -> DepositEntity? {
        guard let (balance, risk) = validate(balanceText, riskPercentText) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            let deposit = try store.add(
                name: trimmedName.isEmpty ? exchange.displayName : trimmedName,
                exchangeIDRaw: exchange.rawValue,
                balance: balance,
                currencyCode: exchange.currencyCode,
                riskPercent: risk
            )
            errorMessage = nil
            reload()
            return deposit
        } catch {
            errorMessage = String(localized: "error_save_deposit")
            return nil
        }
    }

    /// Apply edits to an existing deposit. Returns false on invalid input.
    @discardableResult
    public func updateDeposit(
        _ deposit: DepositEntity,
        name: String,
        balanceText: String,
        riskPercentText: String
    ) -> Bool {
        guard let (balance, risk) = validate(balanceText, riskPercentText) else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        deposit.name = trimmedName.isEmpty ? deposit.name : trimmedName
        deposit.balance = balance
        deposit.riskPercent = risk
        do {
            try store.save()
            errorMessage = nil
            reload()
            return true
        } catch {
            errorMessage = String(localized: "error_save_changes")
            return false
        }
    }

    public func delete(_ deposit: DepositEntity) {
        do {
            try store.delete(deposit)
            reload()
        } catch {
            errorMessage = String(localized: "error_delete_deposit")
        }
    }

    public func delete(at offsets: IndexSet) {
        for index in offsets where deposits.indices.contains(index) {
            delete(deposits[index])
        }
    }

    /// Parse + range-check the numeric fields. `risk` is returned as a fraction
    /// (e.g. 2% → 0.02) to match `DepositEntity.riskPercent` and the engine.
    private func validate(_ balanceText: String, _ riskPercentText: String) -> (balance: Decimal, risk: Decimal)? {
        guard let balance = parseDecimal(balanceText), balance > 0 else {
            errorMessage = String(localized: "error_balance_positive")
            return nil
        }
        guard let riskWhole = parseDecimal(riskPercentText), riskWhole > 0, riskWhole <= 100 else {
            errorMessage = String(localized: "error_risk_range")
            return nil
        }
        return (balance, riskWhole / 100)
    }
}
