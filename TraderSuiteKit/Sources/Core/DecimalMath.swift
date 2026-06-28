import Foundation

/// All monetary math uses `Decimal` to avoid binary floating-point drift.
enum DecimalMath {

    /// Absolute number of ticks between two prices (always >= 0).
    static func ticks(_ a: Decimal, _ b: Decimal, minStep: Decimal) -> Decimal {
        abs(a - b) / minStep
    }

    /// Floors a `Decimal` to a non-negative whole number of lots.
    /// Negative inputs clamp to 0 — you cannot trade a negative number of lots.
    static func floorLots(_ value: Decimal) -> Int {
        guard value > 0 else { return 0 }
        var result = Decimal()
        var input = value
        // For a positive operand, .down == floor.
        NSDecimalRound(&result, &input, 0, .down)
        return NSDecimalNumber(decimal: result).intValue
    }
}
