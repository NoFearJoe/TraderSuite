import Foundation
import Observation
import Core

/// Drives the position-averaging screen for one instrument. SwiftUI-free and
/// pure: existing legs (entry + lots) plus a new leg entry, a common stop and a
/// per-position risk feed the `Averaging` engine, which sizes the new leg.
@MainActor
@Observable
public final class AveragingCalcViewModel {
    /// Standard risk presets, in whole percent.
    public static let presetRiskPercents: [Decimal] = [1, 2, 3, 5]

    /// One already-open leg: an entry price and a (whole) lot count.
    public struct Leg: Identifiable, Hashable {
        public let id = UUID()
        public var entryText: String = ""
        public var lotsText: String = ""
    }

    public var direction: TradeDirection = .long
    public var legs: [Leg] = [Leg()]          // existing positions
    public var newEntryText: String = ""       // the new leg being averaged in
    public var stopText: String = ""           // common stop for all legs
    public var riskChoice: RiskChoice = .preset(1)
    public var customRiskText: String = ""

    public init() {}

    public var riskWholePercent: Decimal? {
        switch riskChoice {
        case .preset(let percent): return percent
        case .custom: return parseDecimal(customRiskText)
        }
    }

    public func applyDepositRisk(_ fraction: Decimal) {
        let whole = fraction * 100
        if Self.presetRiskPercents.contains(whole) {
            riskChoice = .preset(whole)
        } else {
            riskChoice = .custom
            customRiskText = NSDecimalNumber(decimal: whole).stringValue
        }
    }

    // MARK: Draft persistence

    /// A snapshot of the current inputs, for saving between visits.
    var draft: AveragingCalcDraft {
        AveragingCalcDraft(
            isLong: direction == .long,
            legs: legs.map { AveragingLegDraft(entryText: $0.entryText, lotsText: $0.lotsText) },
            newEntryText: newEntryText,
            stopText: stopText,
            risk: riskChoice,
            customRiskText: customRiskText
        )
    }

    /// Restore previously-saved inputs. An empty leg list falls back to one blank
    /// leg so the screen always shows a row to fill.
    func apply(_ draft: AveragingCalcDraft) {
        direction = draft.isLong ? .long : .short
        legs = draft.legs.isEmpty
            ? [Leg()]
            : draft.legs.map { Leg(entryText: $0.entryText, lotsText: $0.lotsText) }
        newEntryText = draft.newEntryText
        stopText = draft.stopText
        riskChoice = draft.risk
        customRiskText = draft.customRiskText
    }

    /// Reset every input to its default (the risk is re-seeded from the deposit
    /// by the view afterwards).
    func clear() {
        direction = .long
        legs = [Leg()]
        newEntryText = ""
        stopText = ""
        riskChoice = .preset(1)
        customRiskText = ""
    }

    public func addLeg() {
        legs.append(Leg())
    }

    public func removeLeg(at offsets: IndexSet) {
        legs.remove(atOffsets: offsets)
    }

    /// A leg is "filled" when it has a valid entry price and a positive lot count.
    public func isFilled(_ leg: Leg) -> Bool {
        guard parseDecimal(leg.entryText) != nil else { return false }
        guard let lots = Int(leg.lotsText.trimmingCharacters(in: .whitespaces)), lots > 0 else { return false }
        return true
    }

    /// The "add position" button is enabled only when every existing leg is filled.
    public var canAddLeg: Bool {
        legs.allSatisfy(isFilled)
    }

    public enum Outcome: Equatable {
        case empty
        case invalid(String)
        case value(AveragingDisplay)
    }

    public func outcome(depositBalance: Decimal?, spec: ContractSpec?) -> Outcome {
        guard let spec else { return .empty }
        guard let depositBalance else { return .invalid(String(localized: "error_select_deposit")) }
        guard let whole = riskWholePercent, whole > 0 else { return .invalid(String(localized: "error_enter_risk")) }
        guard let newEntry = parseDecimal(newEntryText), let stop = parseDecimal(stopText) else { return .empty }

        // Existing legs must all be fully filled before we can size the new one.
        var existing: [ExistingPosition] = []
        for leg in legs {
            guard let entry = parseDecimal(leg.entryText),
                  let lots = Int(leg.lotsText.trimmingCharacters(in: .whitespaces)), lots > 0
            else { return .empty }
            existing.append(ExistingPosition(entry: entry, lots: lots))
        }

        do {
            let result = try Averaging.calculate(
                deposit: depositBalance,
                riskPercentPerPosition: whole / 100,
                direction: direction,
                existing: existing,
                newEntry: newEntry,
                newStop: stop,
                spec: spec,
                commission: CommissionModel(spec: spec, brokerFeePerSide: 0)
            )
            let perPosition = existing.map(\.lots) + [result.newLots]
            return .value(AveragingDisplay(
                newLots: result.newLots,
                totalLots: result.totalLots,
                perPositionLots: perPosition,
                averagePrice: result.newAveragePrice,
                lossAtStop: result.totalRiskAtStop,
                margin: Decimal(result.totalLots) * spec.initialMargin,
                canAdd: result.canAdd,
                limitedByMargin: result.limitedByMargin
            ))
        } catch CalculationError.stopOnWrongSide {
            return .invalid(direction == .long
                ? String(localized: "error_stop_below_entry_new_long")
                : String(localized: "error_stop_above_entry_new_short"))
        } catch CalculationError.nonPositiveDeposit {
            return .invalid(String(localized: "error_deposit_balance_positive"))
        } catch CalculationError.invalidSpec {
            return .invalid(String(localized: "error_invalid_contract_params"))
        } catch {
            return .invalid(String(localized: "error_calculation_failed"))
        }
    }
}

/// Display-ready result of the averaging calculation.
public struct AveragingDisplay: Equatable {
    public let newLots: Int
    public let totalLots: Int
    /// Lots per position: each existing leg, then the new leg last.
    public let perPositionLots: [Int]
    public let averagePrice: Decimal
    public let lossAtStop: Decimal   // total money at the common stop, incl. commission
    public let margin: Decimal       // total initial margin (ГО) for all lots
    public let canAdd: Bool
    public let limitedByMargin: Bool
}
