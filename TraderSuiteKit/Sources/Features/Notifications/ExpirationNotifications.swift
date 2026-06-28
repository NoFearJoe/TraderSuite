import Foundation

/// A scheduled local notification about an upcoming contract expiration.
public struct ExpirationNotification: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

/// Minimal description of a tracked contract for the notification builder —
/// keeps the pure builder independent of SwiftData entities.
public struct WatchlistExpiry: Equatable, Sendable {
    public let family: String
    public let symbol: String
    public let expiration: Date

    public init(family: String, symbol: String, expiration: Date) {
        self.family = family
        self.symbol = symbol
        self.expiration = expiration
    }
}

/// Pure builder that turns tracked contracts into local-notification requests.
/// Unit-testable: no system calls, deterministic given `now`.
public enum ExpirationNotificationBuilder {
    /// Days before the last trading day to remind (and 0 = on the day).
    public static let defaultLeadDays = [5, 1, 0]
    /// Hour of day (in the user's local time zone) to fire reminders.
    public static let hourOfDay = 10

    static var moscowCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let moscow = TimeZone(identifier: "Europe/Moscow") { calendar.timeZone = moscow }
        return calendar
    }

    /// Build reminders for the given contracts. Only fire dates strictly in the
    /// future (relative to `now`) are emitted; one notification per (contract,
    /// lead day) pair, with a stable id so re-scheduling replaces cleanly.
    ///
    /// The contract expiration is an ISS last-trade *date* in Moscow time, so the
    /// trading day is read in `Europe/Moscow`; the reminder then fires at
    /// `hourOfDay` (15:00) in the user's `timeZone` on `(trade date − lead)`.
    public static func build(
        for contracts: [WatchlistExpiry],
        now: Date,
        leadDays: [Int] = defaultLeadDays,
        timeZone: TimeZone = .current
    ) -> [ExpirationNotification] {
        let moscow = moscowCalendar
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone

        var result: [ExpirationNotification] = []
        for contract in contracts {
            // Read the last-trade day in Moscow so the lead-day countdown tracks
            // trading dates, not whatever calendar day the user happens to be on.
            let tradeDay = moscow.dateComponents([.year, .month, .day], from: contract.expiration)
            for lead in leadDays {
                guard let tradeMidnightLocal = local.date(from: tradeDay),
                      let day = local.date(byAdding: .day, value: -lead, to: tradeMidnightLocal),
                      let fire = local.date(
                        bySettingHour: hourOfDay, minute: 0, second: 0, of: day
                      ),
                      fire > now
                else { continue }
                result.append(
                    ExpirationNotification(
                        id: "expiry-\(contract.symbol)-L\(lead)",
                        title: String(localized: "notification_title"),
                        body: body(family: contract.family, symbol: contract.symbol, lead: lead),
                        fireDate: fire
                    )
                )
            }
        }
        return result
    }

    private static func body(family: String, symbol: String, lead: Int) -> String {
        switch lead {
        case 0:  return "\(symbol) (\(family)): \(String(localized: "notification_body_today"))"
        case 1:  return "\(symbol) (\(family)): \(String(localized: "notification_body_tomorrow"))"
        default: return "\(symbol) (\(family)): \(String(format: String(localized: "notification_body_days"), Int64(lead)))"
        }
    }
}
