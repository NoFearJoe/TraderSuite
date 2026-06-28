import Foundation
import Observation
import Core

/// Drives the lot-sizing screen for one instrument. SwiftUI-free and pure so it
/// can be unit-tested: the deposit balance and contract spec are passed in by the
/// view (loaded from persistence / the exchange), the rest is user input.
@MainActor
@Observable
public final class LotCalcViewModel {
    /// Standard risk presets, in whole percent.
    public static let presetRiskPercents: [Decimal] = [1, 2, 3, 5]

    public var direction: TradeDirection = .long
    public var entryText: String = ""
    public var stopText: String = ""
    public var riskChoice: RiskChoice = .preset(1)
    public var customRiskText: String = ""

    public init() {}

    /// Effective risk as a whole percent (e.g. 2 for 2%), or nil if unset/invalid.
    public var riskWholePercent: Decimal? {
        switch riskChoice {
        case .preset(let percent): return percent
        case .custom: return parseDecimal(customRiskText)
        }
    }

    // MARK: Draft persistence

    /// A snapshot of the current inputs, for saving between visits.
    var draft: LotCalcDraft {
        LotCalcDraft(
            isLong: direction == .long,
            entryText: entryText,
            stopText: stopText,
            risk: riskChoice,
            customRiskText: customRiskText
        )
    }

    /// Restore previously-saved inputs.
    func apply(_ draft: LotCalcDraft) {
        direction = draft.isLong ? .long : .short
        entryText = draft.entryText
        stopText = draft.stopText
        riskChoice = draft.risk
        customRiskText = draft.customRiskText
    }

    /// Reset every input to its default (the risk is re-seeded from the deposit
    /// by the view afterwards).
    func clear() {
        direction = .long
        entryText = ""
        stopText = ""
        riskChoice = .preset(1)
        customRiskText = ""
    }

    /// Seed the risk control from a deposit's stored fraction: snap to a preset
    /// when it matches one, otherwise switch to a custom value.
    public func applyDepositRisk(_ fraction: Decimal) {
        let whole = fraction * 100
        if Self.presetRiskPercents.contains(whole) {
            riskChoice = .preset(whole)
        } else {
            riskChoice = .custom
            customRiskText = NSDecimalNumber(decimal: whole).stringValue
        }
    }

    public enum Outcome: Equatable {
        case empty                 // not enough input yet
        case invalid(String)       // a message to show
        case value(LotCalcResult)
    }

    /// Compute the sizing outcome from the current inputs plus the selected
    /// deposit balance and the loaded contract spec.
    public func outcome(depositBalance: Decimal?, spec: ContractSpec?) -> Outcome {
        guard let spec else { return .empty }                 // spec still loading
        guard let depositBalance else { return .invalid(String(localized: "error_select_deposit")) }
        guard let whole = riskWholePercent, whole > 0 else { return .invalid(String(localized: "error_enter_risk")) }
        guard let entry = parseDecimal(entryText), let stop = parseDecimal(stopText) else { return .empty }

        do {
            let result = try PositionSizing.calculate(
                deposit: depositBalance,
                riskPercent: whole / 100,
                direction: direction,
                entry: entry,
                stop: stop,
                spec: spec,
                commission: CommissionModel(spec: spec, brokerFeePerSide: 0)
            )
            return .value(LotCalcResult(
                lots: result.recommendedLots,
                lossAtStop: result.totalRisk,
                margin: Decimal(result.recommendedLots) * spec.initialMargin,
                limitedByMargin: result.limitedByMargin
            ))
        } catch CalculationError.stopOnWrongSide {
            return .invalid(direction == .long
                ? String(localized: "error_stop_below_entry_long")
                : String(localized: "error_stop_above_entry_short"))
        } catch CalculationError.nonPositiveDeposit {
            return .invalid(String(localized: "error_deposit_balance_positive"))
        } catch CalculationError.invalidSpec {
            return .invalid(String(localized: "error_invalid_contract_params"))
        } catch {
            return .invalid(String(localized: "error_calculation_failed"))
        }
    }
}

/// Display-ready result of the lot-sizing calculation.
public struct LotCalcResult: Equatable {
    public let lots: Int
    public let lossAtStop: Decimal   // money lost at the stop for `lots`, incl. commission
    public let margin: Decimal       // total initial margin (ГО) for `lots`
    public let limitedByMargin: Bool
}
