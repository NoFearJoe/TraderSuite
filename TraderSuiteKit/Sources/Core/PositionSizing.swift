import Foundation

/// Result of sizing a single new position.
public struct PositionSizeResult: Sendable, Hashable {
    /// Lots allowed by the risk budget alone.
    public let lotsByRisk: Int
    /// Lots allowed by available margin alone.
    public let lotsByMargin: Int
    /// What you can actually take: min(lotsByRisk, lotsByMargin).
    public let recommendedLots: Int
    /// True when margin — not risk — is the binding constraint.
    public let limitedByMargin: Bool
    /// Money risked per lot if stopped out, incl. round-trip commission.
    public let riskPerLot: Decimal
    /// Total money at risk for `recommendedLots`.
    public let totalRisk: Decimal
}

public enum PositionSizing {

    /// Number of lots for a new trade so that the loss at the stop
    /// (including round-trip commission) does not exceed `deposit * riskPercent`,
    /// also capped by available margin.
    ///
    /// - Parameters:
    ///   - deposit: balance of the selected deposit, in exchange currency.
    ///   - riskPercent: fraction of the deposit to risk, e.g. 0.02 for 2%.
    public static func calculate(
        deposit: Decimal,
        riskPercent: Decimal,
        direction: TradeDirection,
        entry: Decimal,
        stop: Decimal,
        spec: ContractSpec,
        commission: CommissionModel
    ) throws -> PositionSizeResult {
        guard deposit > 0 else { throw CalculationError.nonPositiveDeposit }
        guard spec.minStep > 0, spec.stepPrice > 0, spec.initialMargin > 0 else {
            throw CalculationError.invalidSpec("minStep, stepPrice and initialMargin must be > 0")
        }

        let adverse = direction.adverseTicks(entry: entry, stop: stop, minStep: spec.minStep)
        guard adverse > 0 else { throw CalculationError.stopOnWrongSide }

        let lossPerLot = adverse * spec.stepPrice
        let riskPerLot = lossPerLot + commission.roundTripPerLot
        let riskMoney = deposit * riskPercent

        let lotsByRisk = DecimalMath.floorLots(riskMoney / riskPerLot)
        let lotsByMargin = DecimalMath.floorLots(deposit / spec.initialMargin)
        let recommended = min(lotsByRisk, lotsByMargin)

        return PositionSizeResult(
            lotsByRisk: lotsByRisk,
            lotsByMargin: lotsByMargin,
            recommendedLots: recommended,
            limitedByMargin: lotsByRisk > lotsByMargin,
            riskPerLot: riskPerLot,
            totalRisk: Decimal(recommended) * riskPerLot
        )
    }
}
