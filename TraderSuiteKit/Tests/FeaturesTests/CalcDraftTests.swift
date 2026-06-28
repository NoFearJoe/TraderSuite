import Testing
import Foundation
import Core
@testable import Features

@MainActor
@Suite("Calc drafts")
struct CalcDraftTests {
    @Test("Lot calc draft round-trips through apply()")
    func lotRoundTrip() {
        let model = LotCalcViewModel()
        model.direction = .short
        model.entryText = "100,5"
        model.stopText = "98"
        model.riskChoice = .custom
        model.customRiskText = "2.5"

        let restored = LotCalcViewModel()
        restored.apply(model.draft)

        #expect(restored.direction == .short)
        #expect(restored.entryText == "100,5")
        #expect(restored.stopText == "98")
        #expect(restored.riskChoice == .custom)
        #expect(restored.customRiskText == "2.5")
    }

    @Test("Lot calc draft survives JSON encoding, incl. a custom risk")
    func lotCodable() throws {
        let model = LotCalcViewModel()
        model.entryText = "100"
        model.riskChoice = .custom
        model.customRiskText = "3"

        let data = try JSONEncoder().encode(model.draft)
        let decoded = try JSONDecoder().decode(LotCalcDraft.self, from: data)
        #expect(decoded == model.draft)
    }

    @Test("Clearing resets every field and marks the draft empty")
    func clear() {
        let model = LotCalcViewModel()
        model.entryText = "100"
        model.stopText = "90"
        #expect(!model.draft.isEmpty)

        model.clear()
        #expect(model.draft.isEmpty)
        #expect(model.entryText.isEmpty)
        #expect(model.stopText.isEmpty)
        #expect(model.direction == .long)
    }

    @Test("Averaging draft round-trips legs through apply()")
    func averagingRoundTrip() {
        let model = AveragingCalcViewModel()
        model.legs = [
            .init(entryText: "100", lotsText: "2"),
            .init(entryText: "95", lotsText: "1"),
        ]
        model.newEntryText = "90"
        model.stopText = "85"

        let restored = AveragingCalcViewModel()
        restored.apply(model.draft)

        #expect(restored.legs.count == 2)
        #expect(restored.legs.map(\.entryText) == ["100", "95"])
        #expect(restored.legs.map(\.lotsText) == ["2", "1"])
        #expect(restored.newEntryText == "90")
        #expect(restored.stopText == "85")
    }

    @Test("Applying an empty leg list still yields one blank leg")
    func averagingEmptyLegsFallback() {
        let model = AveragingCalcViewModel()
        model.apply(AveragingCalcDraft())
        #expect(model.legs.count == 1)
    }

    @Test("Averaging clear resets to a single blank leg")
    func averagingClear() {
        let model = AveragingCalcViewModel()
        model.legs = [.init(entryText: "1", lotsText: "1"), .init(entryText: "2", lotsText: "2")]
        model.newEntryText = "3"
        model.clear()
        #expect(model.legs.count == 1)
        #expect(model.draft.isEmpty)
    }
}
