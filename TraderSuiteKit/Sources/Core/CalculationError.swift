import Foundation

public enum CalculationError: Error, Sendable, Equatable {
    /// Deposit must be strictly positive.
    case nonPositiveDeposit
    /// minStep, stepPrice or initialMargin were non-positive.
    case invalidSpec(String)
    /// The stop is not on the loss side of the entry (no risk to size against).
    case stopOnWrongSide
}
