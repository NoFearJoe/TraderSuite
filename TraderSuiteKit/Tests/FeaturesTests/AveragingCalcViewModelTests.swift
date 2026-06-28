import Testing
import Foundation
import Core
@testable import Features

@MainActor
@Suite("AveragingCalcViewModel")
struct AveragingCalcViewModelTests {
    private func spec(margin: Decimal = 1000) -> ContractSpec {
        ContractSpec(symbol: "X", minStep: 1, stepPrice: 1, initialMargin: margin, exchangeFeePerSide: 0)
    }

    @Test("Sizes the new leg and reports per-position lots")
    func sizes() {
        let model = AveragingCalcViewModel()
        model.direction = .long
        model.riskChoice = .preset(2)            // 2%
        model.legs = [leg(entry: "100", lots: "3")]
        model.newEntryText = "90"
        model.stopText = "80"

        // budget = 100_000 * 2% * 2 legs = 4000
        // existing leg risk at stop 80: (100-80)*1*3 = 60
        // remaining = 3940; risk/new lot = (90-80)*1 = 10  => 394 by risk
        // margin: remaining margin (100_000 - 3*1000)=97_000 / 1000 = 97 => margin binds
        guard case .value(let display) = model.outcome(depositBalance: 100_000, spec: spec()) else {
            Issue.record("expected a value outcome"); return
        }
        #expect(display.newLots == 97)
        #expect(display.perPositionLots == [3, 97])
        #expect(display.totalLots == 100)
        #expect(display.limitedByMargin)
        #expect(display.canAdd)
    }

    @Test("Incomplete legs keep the outcome empty")
    func incomplete() {
        let model = AveragingCalcViewModel()
        model.legs = [leg(entry: "100", lots: "")]   // missing lots
        model.newEntryText = "90"
        model.stopText = "80"
        #expect(model.outcome(depositBalance: 100_000, spec: spec()) == .empty)
    }

    @Test("Add button is gated on filled legs")
    func addGate() {
        let model = AveragingCalcViewModel()
        #expect(!model.canAddLeg)                 // empty initial leg
        model.legs = [leg(entry: "100", lots: "2")]
        #expect(model.canAddLeg)
        model.addLeg()
        #expect(!model.canAddLeg)                 // new empty leg
    }

    @Test("Wrong-side stop is reported")
    func wrongSide() {
        let model = AveragingCalcViewModel()
        model.direction = .long
        model.riskChoice = .preset(1)
        model.legs = [leg(entry: "100", lots: "1")]
        model.newEntryText = "90"
        model.stopText = "95"                     // above the new entry on a long
        if case .invalid = model.outcome(depositBalance: 100_000, spec: spec()) {
            // expected
        } else {
            Issue.record("expected an invalid outcome")
        }
    }

    private func leg(entry: String, lots: String) -> AveragingCalcViewModel.Leg {
        var l = AveragingCalcViewModel.Leg()
        l.entryText = entry
        l.lotsText = lots
        return l
    }
}
