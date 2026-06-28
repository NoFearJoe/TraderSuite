import Testing
import Foundation
@testable import Core

/// Shorthand for exact Decimal literals (avoids Double imprecision in tests).
private func d(_ s: String) -> Decimal { Decimal(string: s)! }

/// A simple MOEX-like contract: 1 point = 1 step, 1 RUB per step.
private let siSpec = ContractSpec(
    symbol: "Si-3.25",
    minStep: 1,
    stepPrice: 1,
    initialMargin: 15_000,
    exchangeFeePerSide: 0
)

private let noFees = CommissionModel(exchangeFeePerSide: 0, brokerFeePerSide: 0)

@Suite("Position sizing")
struct PositionSizingTests {

    @Test("Risk-limited long with no commission")
    func riskLimitedLong() throws {
        let r = try PositionSizing.calculate(
            deposit: 1_000_000,
            riskPercent: d("0.02"),
            direction: .long,
            entry: 90_000,
            stop: 89_000,
            spec: siSpec,
            commission: noFees
        )
        // 2% of 1,000,000 = 20,000 budget; loss per lot = 1000 -> 20 lots.
        #expect(r.lotsByRisk == 20)
        #expect(r.recommendedLots == 20)
        #expect(r.limitedByMargin == false)
        #expect(r.totalRisk == 20_000)
    }

    @Test("Commission reduces the lot count")
    func commissionReducesLots() throws {
        let fees = CommissionModel(exchangeFeePerSide: d("2.5"), brokerFeePerSide: d("2.5"))
        let r = try PositionSizing.calculate(
            deposit: 1_000_000,
            riskPercent: d("0.02"),
            direction: .long,
            entry: 90_000,
            stop: 89_000,
            spec: siSpec,
            commission: fees
        )
        // round-trip per lot = (2.5 + 2.5) * 2 = 10.
        // riskPerLot = 1000 + 10 = 1010 -> floor(20000/1010) = 19.
        #expect(r.riskPerLot == 1010)
        #expect(r.recommendedLots == 19)
    }

    @Test("Margin can be the binding constraint")
    func marginLimited() throws {
        let tightMargin = ContractSpec(symbol: "X", minStep: 1, stepPrice: 1, initialMargin: 60_000)
        let r = try PositionSizing.calculate(
            deposit: 1_000_000,
            riskPercent: d("0.02"),
            direction: .long,
            entry: 90_000,
            stop: 89_000,
            spec: tightMargin,
            commission: noFees
        )
        // Risk allows 20 lots, but margin allows floor(1,000,000/60,000) = 16.
        #expect(r.lotsByRisk == 20)
        #expect(r.lotsByMargin == 16)
        #expect(r.recommendedLots == 16)
        #expect(r.limitedByMargin == true)
    }

    @Test("Short sizing mirrors long")
    func shortSizing() throws {
        let r = try PositionSizing.calculate(
            deposit: 1_000_000,
            riskPercent: d("0.02"),
            direction: .short,
            entry: 90_000,
            stop: 91_000,   // stop above entry = loss side for a short
            spec: siSpec,
            commission: noFees
        )
        #expect(r.recommendedLots == 20)
    }

    @Test("Stop on the wrong side throws")
    func wrongSideThrows() {
        #expect(throws: CalculationError.stopOnWrongSide) {
            _ = try PositionSizing.calculate(
                deposit: 1_000_000,
                riskPercent: d("0.02"),
                direction: .long,
                entry: 90_000,
                stop: 91_000,   // above entry: a long does not lose here
                spec: siSpec,
                commission: noFees
            )
        }
    }
}
