import Foundation

/// One already-open leg of the position being averaged.
public struct ExistingPosition: Sendable, Hashable {
    public let entry: Decimal
    public let lots: Int
    public init(entry: Decimal, lots: Int) {
        self.entry = entry
        self.lots = lots
    }
}

public struct AveragingResult: Sendable, Hashable {
    /// Lots to add now (0 if the budget is already exhausted).
    public let newLots: Int
    /// Total lots after adding.
    public let totalLots: Int
    /// New volume-weighted average entry price.
    public let newAveragePrice: Decimal
    /// Price at which the combined position breaks even (covers all commissions).
    public let breakeven: Decimal
    /// Risk budget = deposit * riskPercentPerPosition * (legs incl. the new one).
    public let riskBudget: Decimal
    /// Net risk of the existing legs at the common stop (profitable legs offset).
    public let existingRisk: Decimal
    /// Total money at risk at the common stop after adding `newLots`.
    public let totalRiskAtStop: Decimal
    /// True when margin — not risk — is the binding constraint on `newLots`.
    public let limitedByMargin: Bool
    /// False when existing legs already exceed the budget (newLots == 0).
    public let canAdd: Bool
}

public enum Averaging {

    /// Lots to add when averaging, such that the total loss at a single common
    /// stop (applied to all legs, including the new one) does not exceed
    /// `deposit * riskPercentPerPosition * numberOfPositions`.
    ///
    /// ASSUMPTION: `numberOfPositions` counts ALL legs including the new one
    /// (existing.count + 1). If you want existing legs only, change `positionCount`.
    public static func calculate(
        deposit: Decimal,
        riskPercentPerPosition: Decimal,
        direction: TradeDirection,
        existing: [ExistingPosition],
        newEntry: Decimal,
        newStop: Decimal,
        spec: ContractSpec,
        commission: CommissionModel
    ) throws -> AveragingResult {
        guard deposit > 0 else { throw CalculationError.nonPositiveDeposit }
        guard spec.minStep > 0, spec.stepPrice > 0, spec.initialMargin > 0 else {
            throw CalculationError.invalidSpec("minStep, stepPrice and initialMargin must be > 0")
        }

        // The new leg must carry real risk: stop on its loss side.
        let newAdverse = direction.adverseTicks(entry: newEntry, stop: newStop, minStep: spec.minStep)
        guard newAdverse > 0 else { throw CalculationError.stopOnWrongSide }

        let rt = commission.roundTripPerLot

        let positionCount = existing.count + 1
        let riskBudget = deposit * riskPercentPerPosition * Decimal(positionCount)

        // Aggregate existing legs at the common stop.
        var existingRisk: Decimal = 0          // net (profitable legs offset)
        var existingMarginUsed: Decimal = 0
        var weightedEntry: Decimal = 0
        var existingLots = 0
        for leg in existing {
            let adv = direction.adverseTicks(entry: leg.entry, stop: newStop, minStep: spec.minStep)
            existingRisk += adv * spec.stepPrice * Decimal(leg.lots) + rt * Decimal(leg.lots)
            existingMarginUsed += spec.initialMargin * Decimal(leg.lots)
            weightedEntry += leg.entry * Decimal(leg.lots)
            existingLots += leg.lots
        }

        let remaining = riskBudget - existingRisk
        let riskPerNewLot = newAdverse * spec.stepPrice + rt

        // Budget already blown by existing legs — cannot add.
        guard remaining > 0 else {
            let avg = existingLots > 0 ? weightedEntry / Decimal(existingLots) : newEntry
            return AveragingResult(
                newLots: 0,
                totalLots: existingLots,
                newAveragePrice: avg,
                breakeven: breakeven(direction: direction, average: avg, roundTripPerLot: rt, spec: spec),
                riskBudget: riskBudget,
                existingRisk: existingRisk,
                totalRiskAtStop: existingRisk,
                limitedByMargin: false,
                canAdd: false
            )
        }

        let lotsByRisk = DecimalMath.floorLots(remaining / riskPerNewLot)
        let remainingMargin = deposit - existingMarginUsed
        let lotsByMargin = DecimalMath.floorLots(remainingMargin / spec.initialMargin)
        let newLots = min(lotsByRisk, lotsByMargin)

        let totalLots = existingLots + newLots
        let avg = totalLots > 0
            ? (weightedEntry + newEntry * Decimal(newLots)) / Decimal(totalLots)
            : newEntry
        let totalRiskAtStop = existingRisk + Decimal(newLots) * riskPerNewLot

        return AveragingResult(
            newLots: newLots,
            totalLots: totalLots,
            newAveragePrice: avg,
            breakeven: breakeven(direction: direction, average: avg, roundTripPerLot: rt, spec: spec),
            riskBudget: riskBudget,
            existingRisk: existingRisk,
            totalRiskAtStop: totalRiskAtStop,
            limitedByMargin: lotsByRisk > lotsByMargin,
            canAdd: true
        )
    }

    /// Price that covers round-trip commission on the whole position.
    /// For a long it sits above the average, for a short below it.
    private static func breakeven(
        direction: TradeDirection,
        average: Decimal,
        roundTripPerLot: Decimal,
        spec: ContractSpec
    ) -> Decimal {
        guard spec.stepPrice > 0 else { return average }
        // Per-lot commission expressed in price = (rt / stepPrice) * minStep.
        let shift = (roundTripPerLot / spec.stepPrice) * spec.minStep
        switch direction {
        case .long:  return average + shift
        case .short: return average - shift
        }
    }
}
