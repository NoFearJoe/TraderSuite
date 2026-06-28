import Foundation

/// How close a tracked contract is to its last trading day.
public enum ExpirationStatus: Equatable, Sendable {
    /// No expiration known yet (front contract not resolved).
    case unknown
    /// Comfortably far from expiry.
    case active(daysLeft: Int)
    /// Within the warning window — time to consider rolling.
    case expiringSoon(daysLeft: Int)
    /// Last trading day has passed.
    case expired
}

/// Pure expiration math, separated from UI/storage so it is unit-testable.
/// Dates are compared in Moscow time to match MOEX `LASTTRADEDATE` semantics.
enum ExpirationPolicy {
    /// Contracts within this many days of expiry are flagged "expiring soon".
    static let soonThresholdDays = 5

    private static var moscowCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let moscow = TimeZone(identifier: "Europe/Moscow") { calendar.timeZone = moscow }
        return calendar
    }

    /// Whole calendar days from `now` to `expiration` (negative if already past).
    static func daysLeft(from now: Date, to expiration: Date) -> Int {
        let calendar = moscowCalendar
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: expiration)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func status(
        expiration: Date?,
        now: Date,
        soonThreshold: Int = soonThresholdDays
    ) -> ExpirationStatus {
        guard let expiration else { return .unknown }
        let days = daysLeft(from: now, to: expiration)
        if days < 0 { return .expired }
        if days <= soonThreshold { return .expiringSoon(daysLeft: days) }
        return .active(daysLeft: days)
    }
}
