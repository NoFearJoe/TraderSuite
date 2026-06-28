import Foundation

/// Money formatting for display. Falls back to a plain number if the currency
/// is unknown. Grouping separators on, no fractional digits for whole amounts.
@MainActor
private let moneyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    f.groupingSeparator = " "
    return f
}()

@MainActor
func formatMoney(_ amount: Decimal, currencyCode: String) -> String {
    let number = NSDecimalNumber(decimal: amount)
    let formatted = moneyFormatter.string(from: number) ?? number.stringValue
    return currencyCode.isEmpty ? formatted : "\(formatted) \(currencyCode)"
}

@MainActor
func formatDecimal(_ value: Decimal) -> String {
    moneyFormatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
}

/// Percent for display: a stored fraction (0.02) → "2".
func formatPercent(_ fraction: Decimal) -> String {
    NSDecimalNumber(decimal: fraction * 100).stringValue
}

@MainActor
private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    if let moscow = TimeZone(identifier: "Europe/Moscow") { f.timeZone = moscow }
    return f
}()

/// Expiration date for display (Moscow time, to match MOEX last-trade dates).
@MainActor
func formatDate(_ date: Date) -> String {
    dateFormatter.string(from: date)
}
