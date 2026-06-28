import Foundation

/// Which calculator a saved draft belongs to. The raw value is the persisted
/// `CalcDraftEntity.kindRaw` discriminator.
enum CalcKind: String {
    case lot
    case averaging
}

/// A snapshot of the lot-sizing screen's input fields, persisted between visits.
struct LotCalcDraft: Codable, Equatable {
    var isLong: Bool = true
    var entryText: String = ""
    var stopText: String = ""
    var risk: RiskChoice = .preset(1)
    var customRiskText: String = ""

    /// Nothing worth restoring — the price fields are blank.
    var isEmpty: Bool {
        entryText.trimmingCharacters(in: .whitespaces).isEmpty
            && stopText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// One existing leg in a saved averaging draft.
struct AveragingLegDraft: Codable, Equatable {
    var entryText: String = ""
    var lotsText: String = ""
}

/// A snapshot of the averaging screen's input fields, persisted between visits.
struct AveragingCalcDraft: Codable, Equatable {
    var isLong: Bool = true
    var legs: [AveragingLegDraft] = []
    var newEntryText: String = ""
    var stopText: String = ""
    var risk: RiskChoice = .preset(1)
    var customRiskText: String = ""

    /// Nothing worth restoring — no new entry, no stop, and no filled legs.
    var isEmpty: Bool {
        newEntryText.trimmingCharacters(in: .whitespaces).isEmpty
            && stopText.trimmingCharacters(in: .whitespaces).isEmpty
            && legs.allSatisfy {
                $0.entryText.trimmingCharacters(in: .whitespaces).isEmpty
                    && $0.lotsText.trimmingCharacters(in: .whitespaces).isEmpty
            }
    }
}
