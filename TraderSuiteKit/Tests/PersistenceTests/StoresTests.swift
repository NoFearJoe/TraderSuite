import Testing
import Foundation
import SwiftData
import Core
@testable import Persistence

// Each suite owns an in-memory container as a stored property. swift-testing
// builds a fresh suite instance per test, so this gives both isolation and —
// crucially — keeps the container alive for the test's lifetime: a SwiftData
// `ModelContext` does NOT retain its `ModelContainer`, and `save()` traps if the
// container has been deallocated.

@MainActor
@Suite("Deposit store")
struct DepositStoreTests {
    let container: ModelContainer
    let store: DepositStore

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        store = DepositStore(context: container.mainContext)
    }

    @Test("Add, list, and scope deposits by exchange")
    func addAndList() throws {
        try store.add(
            name: "Основной", exchangeIDRaw: "moex", balance: 1_000_000,
            currencyCode: "RUB", riskPercent: 0.02, now: Date(timeIntervalSince1970: 1)
        )
        try store.add(
            name: "Демо", exchangeIDRaw: "moex", balance: 50_000,
            currencyCode: "RUB", riskPercent: 0.01, now: Date(timeIntervalSince1970: 2)
        )
        try store.add(
            name: "Other", exchangeIDRaw: "other", balance: 1,
            currencyCode: "USD", riskPercent: 0.05, now: Date(timeIntervalSince1970: 3)
        )

        let all = try store.all()
        #expect(all.count == 3)
        #expect(all.first?.name == "Other")  // newest first

        let moex = try store.deposits(forExchange: "moex")
        #expect(moex.count == 2)
        #expect(moex.allSatisfy { $0.exchangeIDRaw == "moex" })
        #expect(moex.first?.name == "Демо")  // newer of the two
    }

    @Test("Edits persist through save()")
    func editPersists() throws {
        let deposit = try store.add(
            name: "A", exchangeIDRaw: "moex", balance: 100,
            currencyCode: "RUB", riskPercent: 0.02
        )

        deposit.balance = 250
        try store.save()

        let reloaded = try store.all()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.balance == 250)
    }

    @Test("Delete removes the deposit")
    func delete() throws {
        let deposit = try store.add(
            name: "A", exchangeIDRaw: "moex", balance: 100,
            currencyCode: "RUB", riskPercent: 0.02
        )

        try store.delete(deposit)
        #expect(try store.all().isEmpty)
    }
}

@MainActor
@Suite("Watchlist store")
struct WatchlistStoreTests {
    let container: ModelContainer
    let store: WatchlistStore

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        store = WatchlistStore(context: container.mainContext)
    }

    @Test("Different contracts of a family coexist; the same contract de-duplicates")
    func dedupByContract() throws {
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-6.26")
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-9.26")
        // Both contracts of the same family are kept.
        #expect(try store.watchlist(forExchange: "moex").count == 2)

        // Re-adding an existing contract is idempotent, not a duplicate.
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-9.26")
        #expect(try store.watchlist(forExchange: "moex").count == 2)
    }

    @Test("Different families coexist; lookup is exchange-scoped")
    func multipleFamilies() throws {
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-6.26")
        try store.add(exchangeIDRaw: "moex", family: "RTS", activeSymbol: "RTS-6.26")

        #expect(try store.watchlist(forExchange: "moex").count == 2)
        #expect(try store.watchlist(family: "Si", exchangeIDRaw: "moex") != nil)
        #expect(try store.watchlist(family: "Si", exchangeIDRaw: "other") == nil)
    }

    @Test("Rolling forward keeps the watchlist, swaps the active symbol")
    func roll() throws {
        let fav = try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-6.26")

        try store.roll(fav, to: "Si-9.26")

        let reloaded = try store.watchlist(family: "Si", exchangeIDRaw: "moex")
        #expect(reloaded?.activeSymbol == "Si-9.26")
        #expect(try store.watchlist(forExchange: "moex").count == 1)
    }

    @Test("Reorder persists an explicit order that survives a reload")
    func reorder() throws {
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-6.26")
        try store.add(exchangeIDRaw: "moex", family: "RTS", activeSymbol: "RTS-6.26")
        try store.add(exchangeIDRaw: "moex", family: "BR", activeSymbol: "BR-6.26")

        // Default order is newest-first: BR, RTS, Si.
        let initial = try store.watchlist(forExchange: "moex")
        #expect(initial.map(\.family) == ["BR", "RTS", "Si"])

        // Move Si to the front, keep the rest in order.
        let reordered = [initial[2], initial[0], initial[1]]   // Si, BR, RTS
        try store.reorder(reordered)

        let afterReload = try store.watchlist(forExchange: "moex").map(\.family)
        #expect(afterReload == ["Si", "BR", "RTS"])
    }

    @Test("Reorder is scoped to the passed entries; other exchanges keep their order")
    func reorderIsExchangeScoped() throws {
        try store.add(exchangeIDRaw: "moex", family: "Si", activeSymbol: "Si-6.26")
        try store.add(exchangeIDRaw: "cme", family: "ES", activeSymbol: "ESM6")
        try store.add(exchangeIDRaw: "cme", family: "NQ", activeSymbol: "NQM6")

        let cme = try store.watchlist(forExchange: "cme")            // NQ, ES (newest first)
        try store.reorder([cme[1], cme[0]])                          // → ES, NQ

        #expect(try store.watchlist(forExchange: "cme").map(\.family) == ["ES", "NQ"])
        // The MOEX entry is untouched and still present.
        #expect(try store.watchlist(forExchange: "moex").map(\.family) == ["Si"])
    }
}

@MainActor
@Suite("Calc draft store")
struct CalcDraftStoreTests {
    let container: ModelContainer
    let store: CalcDraftStore

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        store = CalcDraftStore(context: container.mainContext)
    }

    @Test("Save then read back a draft payload")
    func saveAndRead() throws {
        let payload = Data("hello".utf8)
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot", payload: payload)

        let draft = try store.draft(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot")
        #expect(draft?.payload == payload)
    }

    @Test("Saving the same key updates in place, does not duplicate")
    func upsert() throws {
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot", payload: Data("a".utf8))
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot", payload: Data("b".utf8))

        let all = try container.mainContext.fetch(FetchDescriptor<CalcDraftEntity>())
        #expect(all.count == 1)
        #expect(try store.draft(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot")?.payload == Data("b".utf8))
    }

    @Test("Drafts are scoped by symbol and calculator kind")
    func scoping() throws {
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot", payload: Data("1".utf8))
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "averaging", payload: Data("2".utf8))
        try store.save(exchangeIDRaw: "moex", symbol: "BRX6", kindRaw: "lot", payload: Data("3".utf8))

        #expect(try container.mainContext.fetch(FetchDescriptor<CalcDraftEntity>()).count == 3)
        #expect(try store.draft(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "averaging")?.payload == Data("2".utf8))
        #expect(try store.draft(exchangeIDRaw: "moex", symbol: "BRX6", kindRaw: "averaging") == nil)
    }

    @Test("Delete removes the draft")
    func delete() throws {
        try store.save(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot", payload: Data("x".utf8))
        try store.delete(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot")
        #expect(try store.draft(exchangeIDRaw: "moex", symbol: "SiM6", kindRaw: "lot") == nil)
    }
}

@MainActor
@Suite("Spec cache")
struct SpecCacheTests {
    let container: ModelContainer
    let cache: SpecCache

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        cache = SpecCache(context: container.mainContext)
    }

    private func sampleSpec(_ symbol: String = "Si-6.26", margin: Decimal = 15_000) -> ContractSpec {
        ContractSpec(
            symbol: symbol, minStep: 1, stepPrice: 1,
            initialMargin: margin, exchangeFeePerSide: 2
        )
    }

    @Test("Upsert then read back a fresh spec")
    func upsertAndRead() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        try cache.upsert(sampleSpec(), exchangeIDRaw: "moex", now: t0)

        let spec = try cache.freshSpec(symbol: "Si-6.26", exchangeIDRaw: "moex", now: t0)
        #expect(spec?.initialMargin == 15_000)
        #expect(spec?.exchangeFeePerSide == 2)
    }

    @Test("A stale entry is not returned as fresh, but is kept for offline use")
    func staleNotReturned() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        try cache.upsert(sampleSpec(), exchangeIDRaw: "moex", now: t0)

        let later = t0.addingTimeInterval(SpecCache.defaultMaxAge + 1)
        #expect(try cache.freshSpec(symbol: "Si-6.26", exchangeIDRaw: "moex", now: later) == nil)
        #expect(try cache.entity(symbol: "Si-6.26", exchangeIDRaw: "moex") != nil)
    }

    @Test("Upsert refreshes in place, does not duplicate")
    func upsertRefreshes() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        try cache.upsert(sampleSpec(), exchangeIDRaw: "moex", now: t0)

        let t1 = t0.addingTimeInterval(60)
        try cache.upsert(sampleSpec(margin: 18_000), exchangeIDRaw: "moex", now: t1)

        let all = try container.mainContext.fetch(FetchDescriptor<CachedSpecEntity>())
        #expect(all.count == 1)
        #expect(all.first?.initialMargin == 18_000)
        #expect(all.first?.updatedAt == t1)
    }

    @Test("purgeStale removes only old entries")
    func purgeStale() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        try cache.upsert(sampleSpec("Si-6.26"), exchangeIDRaw: "moex", now: t0)
        try cache.upsert(sampleSpec("RTS-6.26"), exchangeIDRaw: "moex",
                         now: t0.addingTimeInterval(SpecCache.defaultMaxAge))

        let now = t0.addingTimeInterval(SpecCache.defaultMaxAge + 10)
        let removed = try cache.purgeStale(now: now)
        #expect(removed == 1)
        #expect(try cache.entity(symbol: "Si-6.26", exchangeIDRaw: "moex") == nil)
        #expect(try cache.entity(symbol: "RTS-6.26", exchangeIDRaw: "moex") != nil)
    }
}

@MainActor
@Suite("Container")
struct ContainerTests {

    @Test("In-memory container builds with the full schema")
    func buildsInMemory() throws {
        let container = try PersistenceContainer.make(inMemory: true)
        #expect(PersistenceContainer.schema.entities.count == 4)
        let store = DepositStore(context: container.mainContext)
        #expect(try store.all().isEmpty)
    }
}
