import Testing
import Foundation
import SwiftData
import Core
import ExchangeKit
import Persistence
@testable import Features

private func mskDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return cal.date(from: DateComponents(year: y, month: m, day: d))!
}

private struct ListAdapter: ExchangeAdapter {
    let exchangeID: ExchangeID = .moex
    let instruments: [InstrumentSummary]
    func fetchInstruments() async throws -> [InstrumentSummary] { instruments }
    func fetchSpec(symbol: String) async throws -> ContractSpec {
        ContractSpec(symbol: symbol, minStep: 1, stepPrice: 1, initialMargin: 1)
    }
    func resolveFrontContract(family: String) async throws -> ContractSpec {
        try await fetchSpec(symbol: frontInstrument(family: family).symbol)
    }
}

private actor SpyScheduler: NotificationScheduling {
    private(set) var lastReminders: [ExpirationNotification] = []
    func requestAuthorization() async -> Bool { true }
    func replaceExpirationReminders(_ notifications: [ExpirationNotification]) async {
        lastReminders = notifications
    }
}

@MainActor
@Suite("WatchlistViewModel")
struct WatchlistViewModelTests {
    let container: ModelContainer
    let store: WatchlistStore
    let registry: ExchangeRegistry
    private let scheduler = SpyScheduler()
    let model: WatchlistViewModel

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        store = WatchlistStore(context: container.mainContext)
        registry = ExchangeRegistry(adapters: [ListAdapter(instruments: [
            InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18)),
            InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18)),
        ])])
        model = WatchlistViewModel(store: store, registry: registry, scheduler: scheduler)
    }

    @Test("Adding a family resolves and stores the front contract")
    func addResolvesFront() async {
        let ok = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 14))
        #expect(ok)
        #expect(model.watchlist.count == 1)
        #expect(model.watchlist.first?.activeSymbol == "SiM6")
        #expect(model.watchlist.first?.activeExpiration == mskDay(2026, 6, 18))
    }

    @Test("Adding another contract of a tracked family keeps both")
    func addSecondContractKeepsBoth() async {
        let si6 = InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18))
        let si9 = InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18))
        _ = await model.addWatchlist(contract: si6, exchange: .moex)
        _ = await model.addWatchlist(contract: si9, exchange: .moex)
        #expect(model.watchlist.count == 2)
        #expect(Set(model.watchlist.map(\.activeSymbol)) == ["SiM6", "SiU6"])

        // Re-adding an existing contract does not duplicate it.
        _ = await model.addWatchlist(contract: si9, exchange: .moex)
        #expect(model.watchlist.count == 2)
    }

    @Test("Adding does not schedule reminders until notification is enabled")
    func addDoesNotScheduleByDefault() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 1))
        let reminders = await scheduler.lastReminders
        #expect(reminders.isEmpty)
    }

    @Test("Enabling notification schedules a reminder at the chosen lead time")
    func enableNotificationSchedules() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 1))
        let watchlist = try! #require(model.watchlist.first)
        await model.setNotification(for: watchlist, enabled: true, leadDays: 3, now: mskDay(2026, 6, 1))
        let reminders = await scheduler.lastReminders
        #expect(!reminders.isEmpty)
        #expect(reminders.allSatisfy { $0.id.hasPrefix("expiry-SiM6") })
        // Should fire 3 days before expiration (2026-06-18 → 2026-06-15)
        #expect(reminders.allSatisfy { $0.id.contains("-L3") })
    }

    @Test("Unknown family reports an error and adds nothing")
    func unknownFamily() async {
        let ok = await model.addWatchlist(family: "ZZ", exchange: .moex, now: mskDay(2026, 6, 14))
        #expect(!ok)
        #expect(model.watchlist.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test("Expiration status reflects the active contract")
    func status() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 1))
        let watchlist = try! #require(model.watchlist.first)
        #expect(model.status(for: watchlist, now: mskDay(2026, 6, 1)) == .active(daysLeft: 17))
        #expect(model.status(for: watchlist, now: mskDay(2026, 6, 15)) == .expiringSoon(daysLeft: 3))
        #expect(model.status(for: watchlist, now: mskDay(2026, 6, 19)) == .expired)
    }

    @Test("Auto-rollover rolls an expired watchlist to the next contract")
    func autoRollover() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 14))
        let rolled = await model.rolloverExpired(now: mskDay(2026, 6, 19))
        #expect(rolled == 1)
        #expect(model.watchlist.first?.activeSymbol == "SiU6")
        #expect(model.watchlist.first?.activeExpiration == mskDay(2026, 9, 18))
    }

    @Test("Auto-rollover drops an expired contract instead of duplicating a tracked front")
    func rolloverDoesNotDuplicate() async {
        let si6 = InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18))
        let si9 = InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18))
        _ = await model.addWatchlist(contract: si6, exchange: .moex)
        _ = await model.addWatchlist(contract: si9, exchange: .moex)

        // After Si-6.26 expires, its front is the already-tracked Si-9.26.
        let rolled = await model.rolloverExpired(now: mskDay(2026, 6, 19))
        #expect(rolled == 1)
        #expect(model.watchlist.map(\.activeSymbol) == ["SiU6"])
    }

    @Test("Rollover is a no-op while the contract is still active")
    func noRolloverWhenActive() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 14))
        let rolled = await model.rolloverExpired(now: mskDay(2026, 6, 14))
        #expect(rolled == 0)
        #expect(model.watchlist.first?.activeSymbol == "SiM6")
    }

    @Test("Per-exchange count scopes the free-tier limit to each exchange")
    func countIsPerExchange() async {
        let si6 = InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18))
        let si9 = InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18))
        let es = InstrumentSummary(symbol: "ESM6", family: "ES", displayName: "E-mini S&P", isPerpetual: false, expiration: mskDay(2026, 6, 19))

        _ = await model.addWatchlist(contract: si6, exchange: .moex)
        _ = await model.addWatchlist(contract: si9, exchange: .moex)
        _ = await model.addWatchlist(contract: es, exchange: .cme)

        #expect(model.watchlist.count == 3)
        #expect(model.count(for: .moex) == 2)
        #expect(model.count(for: .cme) == 1)
    }

    @Test("Remove deletes the watchlist")
    func remove() async {
        _ = await model.addWatchlist(family: "Si", exchange: .moex, now: mskDay(2026, 6, 14))
        let watchlist = try! #require(model.watchlist.first)
        model.remove(watchlist)
        #expect(model.watchlist.isEmpty)
    }

    @Test("Move reorders the watchlist and persists the new order")
    func move() async {
        let si6 = InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18))
        let si9 = InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18))
        _ = await model.addWatchlist(contract: si6, exchange: .moex)
        _ = await model.addWatchlist(contract: si9, exchange: .moex)
        // Newest first: SiU6, SiM6.
        #expect(model.watchlist.map(\.activeSymbol) == ["SiU6", "SiM6"])

        // Drag the first row down past the second.
        model.move(model.watchlist, from: IndexSet(integer: 0), to: 2)
        #expect(model.watchlist.map(\.activeSymbol) == ["SiM6", "SiU6"])
    }
}
