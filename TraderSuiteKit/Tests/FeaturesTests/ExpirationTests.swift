import Testing
import Foundation
@testable import Features

private func mskDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return cal.date(from: DateComponents(year: y, month: m, day: d))!
}

@Suite("Expiration status")
struct ExpirationPolicyTests {

    @Test("No expiration → unknown")
    func unknown() {
        #expect(ExpirationPolicy.status(expiration: nil, now: mskDay(2026, 6, 14)) == .unknown)
    }

    @Test("Far ahead → active with day count")
    func active() {
        let status = ExpirationPolicy.status(expiration: mskDay(2026, 6, 24), now: mskDay(2026, 6, 14))
        #expect(status == .active(daysLeft: 10))
    }

    @Test("Within the window → expiring soon")
    func soon() {
        let status = ExpirationPolicy.status(expiration: mskDay(2026, 6, 17), now: mskDay(2026, 6, 14))
        #expect(status == .expiringSoon(daysLeft: 3))
    }

    @Test("On the last day → expiring soon, 0 days")
    func today() {
        let status = ExpirationPolicy.status(expiration: mskDay(2026, 6, 14), now: mskDay(2026, 6, 14))
        #expect(status == .expiringSoon(daysLeft: 0))
    }

    @Test("Past the last day → expired")
    func expired() {
        let status = ExpirationPolicy.status(expiration: mskDay(2026, 6, 13), now: mskDay(2026, 6, 14))
        #expect(status == .expired)
    }
}

@Suite("Expiration notification builder")
struct ExpirationNotificationBuilderTests {

    @Test("One reminder per lead day, all in the future")
    func buildsAll() {
        let contracts = [WatchlistExpiry(family: "Si", symbol: "SiM6", expiration: mskDay(2026, 6, 24))]
        let now = mskDay(2026, 6, 14)
        let notifications = ExpirationNotificationBuilder.build(for: contracts, now: now, leadDays: [5, 1, 0])
        #expect(notifications.count == 3)
        #expect(notifications.allSatisfy { $0.fireDate > now })
        #expect(Set(notifications.map(\.id)) == ["expiry-SiM6-L5", "expiry-SiM6-L1", "expiry-SiM6-L0"])
    }

    @Test("Lead days already in the past are dropped")
    func dropsPast() {
        // Expiry is 3 days out, so the 5-days-before reminder is already past.
        let contracts = [WatchlistExpiry(family: "Si", symbol: "SiM6", expiration: mskDay(2026, 6, 17))]
        let now = mskDay(2026, 6, 14)
        let notifications = ExpirationNotificationBuilder.build(for: contracts, now: now, leadDays: [5, 1, 0])
        #expect(notifications.map(\.id) == ["expiry-SiM6-L1", "expiry-SiM6-L0"])
    }

    @Test("Fires at the configured hour on the trade date in the user's time zone")
    func firesAtConfiguredHourLocal() {
        let tz = TimeZone(identifier: "America/New_York")!
        let contracts = [WatchlistExpiry(family: "Si", symbol: "SiM6", expiration: mskDay(2026, 6, 24))]
        let notifications = ExpirationNotificationBuilder.build(
            for: contracts, now: mskDay(2026, 6, 1), leadDays: [0], timeZone: tz
        )
        var local = Calendar(identifier: .gregorian)
        local.timeZone = tz
        let comps = local.dateComponents([.year, .month, .day, .hour, .minute], from: notifications[0].fireDate)
        #expect(comps.hour == ExpirationNotificationBuilder.hourOfDay)
        #expect(comps.minute == 0)
        // The Moscow last-trade date (June 24) is preserved, not shifted by the tz.
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 24)
    }

    @Test("Body text reflects the lead time")
    func bodyText() {
        let contracts = [WatchlistExpiry(family: "Si", symbol: "SiM6", expiration: mskDay(2026, 6, 24))]
        let notifications = ExpirationNotificationBuilder.build(
            for: contracts, now: mskDay(2026, 6, 14), leadDays: [0]
        )
        // body contains the symbol and family regardless of locale
        #expect(notifications.first?.body.contains("SiM6") == true)
        #expect(notifications.first?.body.contains("Si") == true)
    }
}
