import Foundation

/// Direction of a futures position.
public enum TradeDirection: Sendable, Hashable {
    case long
    case short
}

extension TradeDirection {
    /// Signed adverse move from `entry` to `stop`, expressed in ticks.
    ///
    /// Positive  => the leg LOSES money at `stop` (stop is on the loss side of entry).
    /// Negative  => the leg is in PROFIT at `stop` (e.g. when averaging up).
    ///
    /// For a long, loss happens when the stop is below entry; for a short, above.
    func adverseTicks(entry: Decimal, stop: Decimal, minStep: Decimal) -> Decimal {
        switch self {
        case .long:  return (entry - stop) / minStep
        case .short: return (stop - entry) / minStep
        }
    }
}
