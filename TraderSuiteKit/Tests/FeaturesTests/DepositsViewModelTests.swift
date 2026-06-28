import Testing
import Foundation
import SwiftData
import Core
import ExchangeKit
import Persistence
@testable import Features

@MainActor
@Suite("DepositsViewModel")
struct DepositsViewModelTests {
    let container: ModelContainer       // retained for the test's lifetime
    let model: DepositsViewModel

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        model = DepositsViewModel(store: DepositStore(context: container.mainContext))
    }

    @Test("Add stores a deposit with risk as a fraction")
    func addValid() {
        let created = model.addDeposit(
            name: "Основной", exchange: .moex, balanceText: "1 000 000", riskPercentText: "2"
        )
        #expect(created != nil)
        #expect(model.deposits.count == 1)
        #expect(model.deposits.first?.balance == 1_000_000)
        #expect(model.deposits.first?.riskPercent == Decimal(string: "0.02"))
        #expect(model.deposits.first?.currencyCode == "RUB")
        #expect(model.errorMessage == nil)
    }

    @Test("Blank name falls back to the exchange name")
    func blankNameDefaults() {
        let created = model.addDeposit(
            name: "   ", exchange: .moex, balanceText: "500000", riskPercentText: "1"
        )
        #expect(created?.name == "MOEX")
    }

    @Test("Rejects a non-positive balance")
    func rejectsBadBalance() {
        let created = model.addDeposit(
            name: "x", exchange: .moex, balanceText: "0", riskPercentText: "2"
        )
        #expect(created == nil)
        #expect(model.deposits.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test("Rejects risk outside 0–100")
    func rejectsBadRisk() {
        #expect(model.addDeposit(name: "x", exchange: .moex, balanceText: "100", riskPercentText: "150") == nil)
        #expect(model.addDeposit(name: "x", exchange: .moex, balanceText: "100", riskPercentText: "0") == nil)
    }

    @Test("Update edits the stored deposit")
    func update() throws {
        let deposit = try #require(
            model.addDeposit(name: "A", exchange: .moex, balanceText: "100", riskPercentText: "2")
        )
        let ok = model.updateDeposit(deposit, name: "B", balanceText: "250", riskPercentText: "3")
        #expect(ok)
        #expect(model.deposits.first?.name == "B")
        #expect(model.deposits.first?.balance == 250)
        #expect(model.deposits.first?.riskPercent == Decimal(string: "0.03"))
    }

    @Test("Delete removes the deposit")
    func delete() throws {
        let deposit = try #require(
            model.addDeposit(name: "A", exchange: .moex, balanceText: "100", riskPercentText: "2")
        )
        model.delete(deposit)
        #expect(model.deposits.isEmpty)
    }
}
