import Testing
import Foundation
import Core
@testable import Features

@MainActor
@Suite("LotCalcViewModel")
struct LotCalcViewModelTests {
    private func spec(margin: Decimal = 5000) -> ContractSpec {
        ContractSpec(symbol: "X", minStep: 1, stepPrice: 1, initialMargin: margin, exchangeFeePerSide: 0)
    }

    @Test("Sizes a long trade, capped by margin")
    func sizesLong() {
        let model = LotCalcViewModel()
        model.direction = .long
        model.riskChoice = .preset(2)      // 2%
        model.entryText = "100"
        model.stopText = "90"

        let outcome = model.outcome(depositBalance: 100_000, spec: spec())
        #expect(outcome == .value(LotCalcResult(
            lots: 20,                       // min(risk 200, margin 20)
            lossAtStop: 200,                // 20 lots * 10 loss/lot
            margin: 100_000,                // 20 lots * 5000 ГО
            limitedByMargin: true
        )))
    }

    @Test("Stop on the wrong side is reported")
    func wrongSide() {
        let model = LotCalcViewModel()
        model.direction = .long
        model.riskChoice = .preset(1)
        model.entryText = "100"
        model.stopText = "110"             // above entry on a long => no loss

        if case .invalid = model.outcome(depositBalance: 100_000, spec: spec()) {
            // correct — stop on the wrong side for a long
        } else {
            Issue.record("expected an invalid outcome")
        }
    }

    @Test("No prices yet => empty, no error")
    func empty() {
        let model = LotCalcViewModel()
        #expect(model.outcome(depositBalance: 100_000, spec: spec()) == .empty)
    }

    @Test("No spec yet => empty while it loads")
    func noSpec() {
        let model = LotCalcViewModel()
        model.entryText = "100"
        model.stopText = "90"
        #expect(model.outcome(depositBalance: 100_000, spec: nil) == .empty)
    }

    @Test("Custom risk snaps from a deposit fraction")
    func customRisk() {
        let model = LotCalcViewModel()
        model.applyDepositRisk(0.025)      // 2.5% is not a preset
        #expect(model.riskChoice == .custom)
        #expect(model.riskWholePercent == 2.5)

        model.applyDepositRisk(0.02)       // 2% is a preset
        #expect(model.riskChoice == .preset(2))
    }
}
