import Testing
import Foundation
@testable import Core

private func d(_ s: String) -> Decimal { Decimal(string: s)! }

private let siSpec = ContractSpec(
    symbol: "Si-3.25",
    minStep: 1,
    stepPrice: 1,
    initialMargin: 15_000,
    exchangeFeePerSide: 0
)

private let noFees = CommissionModel(exchangeFeePerSide: 0, brokerFeePerSide: 0)

@Suite("Averaging")
struct AveragingTests {

    @Test("Adds lots within the per-position budget")
    func basicAveraging() throws {
        let r = try Averaging.calculate(
            deposit: 1_000_000,
            riskPercentPerPosition: d("0.02"),
            direction: .long,
            existing: [ExistingPosition(entry: 90_000, lots: 10)],
            newEntry: 89_000,
            newStop: 88_500,
            spec: siSpec,
            commission: noFees
        )
        // 2 legs => budget = 1,000,000 * 0.02 * 2 = 40,000.
        // Existing loss at 88,500 = 1500 * 10 = 15,000 -> remaining 25,000.
        // riskPerNewLot = 500 -> 50 lots (margin allows 56, so risk binds).
        #expect(r.riskBudget == 40_000)
        #expect(r.existingRisk == 15_000)
        #expect(r.newLots == 50)
        #expect(r.totalLots == 60)
        #expect(r.limitedByMargin == false)
        #expect(r.canAdd == true)
        // Total risk at the common stop equals the full budget.
        #expect(r.totalRiskAtStop == 40_000)
        // Weighted average = (90000*10 + 89000*50) / 60.
        #expect(r.newAveragePrice == d("5350000") / 60)
    }

    @Test("A leg in profit at the stop frees budget (averaging up)")
    func profitableLegOffsets() throws {
        let r = try Averaging.calculate(
            deposit: 1_000_000,
            riskPercentPerPosition: d("0.02"),
            direction: .long,
            existing: [ExistingPosition(entry: 88_000, lots: 10)],
            newEntry: 89_000,
            newStop: 88_500,  // existing leg is +500 ticks here
            spec: siSpec,
            commission: noFees
        )
        // Existing "risk" is negative (-5,000): it's in profit at the stop.
        #expect(r.existingRisk == -5_000)
        // remaining = 40,000 + 5,000 = 45,000 -> riskPerNewLot 500 -> 90 lots by risk,
        // but free margin allows floor((1,000,000 - 150,000)/15,000) = 56.
        #expect(r.newLots == 56)
        #expect(r.limitedByMargin == true)
    }

    @Test("Budget already exhausted: cannot add")
    func budgetExhausted() throws {
        let r = try Averaging.calculate(
            deposit: 1_000_000,
            riskPercentPerPosition: d("0.02"),
            direction: .long,
            existing: [ExistingPosition(entry: 90_000, lots: 100)],
            newEntry: 89_000,
            newStop: 88_500,
            spec: siSpec,
            commission: noFees
        )
        // Existing loss = 1500 * 100 = 150,000 > budget 40,000.
        #expect(r.canAdd == false)
        #expect(r.newLots == 0)
        #expect(r.newAveragePrice == 90_000)
    }

    @Test("Breakeven shifts by commission")
    func breakevenWithCommission() throws {
        let fees = CommissionModel(exchangeFeePerSide: d("2.5"), brokerFeePerSide: d("2.5"))
        let r = try Averaging.calculate(
            deposit: 1_000_000,
            riskPercentPerPosition: d("0.02"),
            direction: .long,
            existing: [ExistingPosition(entry: 90_000, lots: 10)],
            newEntry: 90_000,
            newStop: 89_000,
            spec: siSpec,
            commission: fees
        )
        // Average = 90,000; round-trip per lot = (2.5+2.5)*2 = 10; stepPrice 1, minStep 1
        // -> breakeven = 90,000 + 10 = 90,010 (a long must clear fees above average).
        #expect(r.newAveragePrice == 90_000)
        #expect(r.breakeven == 90_010)
    }
}
