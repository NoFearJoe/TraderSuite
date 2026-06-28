import Foundation
import SwiftData
import Core
import ExchangeKit
import Persistence

/// Deterministic in-memory environments + demo data used **only** for App Store
/// asset capture (screenshots and preview videos), driven by the UI-test target.
/// None of this ships in a normal launch — it is reached solely when the app is
/// started with a UI-test launch argument.
///
/// - `-UITestScreenshots` boots a pre-populated watchlist for still screenshots.
/// - `-UITestVideo` boots a reduced watchlist so the preview can show adding an
///   instrument from search, then sizing a position.
/// - `-UITestProUnlocked` forces the PRO entitlement (no paywall, no caps).
///
/// RU runs showcase MOEX data; every other language showcases CME.
public enum UITestMode {
    static let screenshotsFlag = "-UITestScreenshots"
    static let videoFlag = "-UITestVideo"
    static let proFlag = "-UITestProUnlocked"

    private static var args: [String] { ProcessInfo.processInfo.arguments }

    public static var isScreenshots: Bool { args.contains(screenshotsFlag) }
    public static var isVideo: Bool { args.contains(videoFlag) }
    /// Any demo capture mode — used by views to expand result cards and skip the
    /// auto-focus that would otherwise raise the keyboard at the wrong moment.
    public static var isActive: Bool { isScreenshots || isVideo }
    public static var proUnlocked: Bool { args.contains(proFlag) }

    // MARK: Video timing markers
    //
    // The recorder (`scripts/record_preview.sh`) can't see when the app becomes
    // foreground, so in video mode the app drops marker files the script polls
    // (via `simctl get_app_container`): it starts recording on `start` and stops
    // on `end`. This bounds the clip to the demo, excluding XCUITest's launch /
    // teardown springboard. No-ops outside video mode.

    private static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static func writeMarker(_ name: String) {
        guard isVideo, let url = documents?.appendingPathComponent("uitest.\(name)") else { return }
        try? Data("1".utf8).write(to: url)
    }

    static func clearMarkers() {
        guard let documents else { return }
        for name in ["start", "end"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent("uitest.\(name)"))
        }
    }
}

@MainActor
public extension AppEnvironment {
    /// Throwaway, fully-seeded environment for still screenshots (real adapters;
    /// fully offline because every needed spec is pre-cached).
    static func makeForScreenshots() -> AppEnvironment {
        let env = makeDemoEnvironment(registry: makeDefaultRegistry())
        ScreenshotSeed.populate(env)
        return env
    }

    /// Throwaway environment for the preview video. Uses an offline stub adapter
    /// so search returns canned results deterministically (no network), and
    /// starts with a reduced watchlist so the video can add an instrument.
    static func makeForVideo() -> AppEnvironment {
        let showcase = DemoCatalog.showcase
        let registry = ExchangeRegistry(adapters: [DemoStubAdapter(exchange: showcase)])
        let env = makeDemoEnvironment(registry: registry)
        UITestMode.clearMarkers() // drop any stale timing markers from a prior run
        VideoSeed.populate(env, showcase: showcase)
        return env
    }

    private static func makeDemoEnvironment(registry: ExchangeRegistry) -> AppEnvironment {
        // Onboarding must not cover the first frame we capture.
        UserDefaults.standard.set(true, forKey: "onboarding.completed")
        let container = try! PersistenceContainer.make(inMemory: true)
        return AppEnvironment(
            container: container,
            registry: registry,
            notificationScheduler: NoopNotificationScheduler()
        )
    }
}

// MARK: - Demo catalogue

/// One instrument's display data + numeric spec for the demo exchanges.
struct DemoInstrument {
    let family: String
    let symbol: String
    let name: String
    let spec: ContractSpec
}

/// A showcase exchange: its deposits, instruments, and the "hero" instrument the
/// video adds and sizes.
struct DemoExchange {
    let id: ExchangeID
    let currency: String
    let expiration: Date
    let deposits: [(name: String, balance: Decimal, risk: Decimal)]
    let instruments: [DemoInstrument]
    /// Symbol added + sized in the video (excluded from the video's start state).
    let heroSymbol: String
    /// Watchlist the video starts with (the hero is added live from search).
    let videoStartSymbols: [String]

    var heroInstrument: DemoInstrument { instruments.first { $0.symbol == heroSymbol }! }
}

@MainActor
enum DemoCatalog {
    /// Showcase exchange chosen from the run's language: RU → MOEX, else → CME.
    static var showcase: DemoExchange {
        let lang = (Locale.preferredLanguages.first ?? "en").prefix(2).lowercased()
        return lang == "ru" ? moex : cme
    }

    static let moex = DemoExchange(
        id: .moex,
        currency: "RUB",
        expiration: date(2026, 9, 15),
        deposits: [("Основной счёт", 500_000, 0.02), ("Скальпинг", 150_000, 0.01)],
        instruments: [
            DemoInstrument(family: "Si",   symbol: "Si-9.26",   name: "Доллар-рубль", spec: ContractSpec(symbol: "Si-9.26",   minStep: 1,    stepPrice: 1,  initialMargin: 12_000, exchangeFeePerSide: 0.5)),
            DemoInstrument(family: "RTS",  symbol: "RTS-9.26",  name: "Индекс РТС",    spec: ContractSpec(symbol: "RTS-9.26",  minStep: 10,   stepPrice: 13, initialMargin: 22_000, exchangeFeePerSide: 1)),
            DemoInstrument(family: "BR",   symbol: "BR-9.26",   name: "Нефть Brent",   spec: ContractSpec(symbol: "BR-9.26",   minStep: 0.01, stepPrice: 7,  initialMargin: 18_000, exchangeFeePerSide: 1)),
            DemoInstrument(family: "GAZR", symbol: "GAZR-9.26", name: "Газпром",       spec: ContractSpec(symbol: "GAZR-9.26", minStep: 1,    stepPrice: 1,  initialMargin: 3_000,  exchangeFeePerSide: 0.5)),
            DemoInstrument(family: "SBRF", symbol: "SBRF-9.26", name: "Сбербанк",      spec: ContractSpec(symbol: "SBRF-9.26", minStep: 1,    stepPrice: 1,  initialMargin: 4_000,  exchangeFeePerSide: 0.5)),
        ],
        heroSymbol: "Si-9.26",
        videoStartSymbols: ["RTS-9.26", "BR-9.26"]
    )

    static let cme = DemoExchange(
        id: .cme,
        currency: "USD",
        expiration: date(2026, 9, 18),
        deposits: [("Main account", 150_000, 0.01), ("Swing", 40_000, 0.02)],
        instruments: [
            DemoInstrument(family: "ES",  symbol: "ESU6",  name: "E-mini S&P 500",       spec: ContractSpec(symbol: "ESU6",  minStep: 0.25, stepPrice: 12.5, initialMargin: 13_200, exchangeFeePerSide: 2.32)),
            DemoInstrument(family: "NQ",  symbol: "NQU6",  name: "E-mini Nasdaq-100",    spec: ContractSpec(symbol: "NQU6",  minStep: 0.25, stepPrice: 5,    initialMargin: 19_000, exchangeFeePerSide: 2.32)),
            DemoInstrument(family: "CL",  symbol: "CLU6",  name: "Crude Oil WTI",        spec: ContractSpec(symbol: "CLU6",  minStep: 0.01, stepPrice: 10,   initialMargin: 6_500,  exchangeFeePerSide: 2.5)),
            DemoInstrument(family: "GC",  symbol: "GCQ6",  name: "Gold",                 spec: ContractSpec(symbol: "GCQ6",  minStep: 0.1,  stepPrice: 10,   initialMargin: 11_000, exchangeFeePerSide: 2.5)),
            DemoInstrument(family: "MES", symbol: "MESU6", name: "Micro E-mini S&P 500", spec: ContractSpec(symbol: "MESU6", minStep: 0.25, stepPrice: 1.25, initialMargin: 1_320,  exchangeFeePerSide: 0.62)),
        ],
        heroSymbol: "ESU6",
        videoStartSymbols: ["NQU6", "CLU6"]
    )

    /// Fixed calendar date in Europe/Moscow (matches how the app treats expiry).
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

// MARK: - Offline stub adapter (video search)

/// Returns the demo catalogue without any network, so the video's search step is
/// deterministic and works offline. Only the read paths the video exercises are
/// implemented.
struct DemoStubAdapter: ExchangeAdapter {
    let exchange: DemoExchange
    var exchangeID: ExchangeID { exchange.id }

    func fetchInstruments() async throws -> [InstrumentSummary] {
        exchange.instruments.map {
            InstrumentSummary(
                symbol: $0.symbol, family: $0.family, displayName: $0.name,
                isPerpetual: false, expiration: exchange.expiration, iconURL: nil)
        }
    }

    func fetchSpec(symbol: String) async throws -> ContractSpec {
        guard let found = exchange.instruments.first(where: { $0.symbol == symbol }) else {
            throw ExchangeError.instrumentNotFound(symbol)
        }
        return found.spec
    }

    func resolveFrontContract(family: String) async throws -> ContractSpec {
        guard let found = exchange.instruments.first(where: { $0.family == family }) else {
            throw ExchangeError.instrumentNotFound(family)
        }
        return found.spec
    }
}

// MARK: - Seeding

@MainActor
enum ScreenshotSeed {
    static func populate(_ env: AppEnvironment) {
        let ex = DemoCatalog.showcase
        env.selectedExchange = ex.id
        let main = seedDeposits(env, ex)
        env.selectedDepositID = main

        // Full watchlist, hero first, with specs cached so calc works offline.
        var ordered: [WatchlistEntity] = []
        for inst in ex.instruments {
            let entity = try! env.watchlist.add(
                exchangeIDRaw: ex.id.rawValue, family: inst.family,
                activeSymbol: inst.symbol, displayName: inst.name,
                activeExpiration: ex.expiration, iconURLString: nil)
            ordered.append(entity)
            try! env.specCache.upsert(inst.spec, exchangeIDRaw: ex.id.rawValue, expiration: ex.expiration)
        }
        try! env.watchlist.reorder(ordered)

        // Pre-fill the hero's calculators so the still screenshots show a result.
        DemoDrafts.saveLot(env, ex: ex, symbol: ex.heroSymbol,
                           entry: ex.id == .moex ? "92000" : "5600.00",
                           stop:  ex.id == .moex ? "91200" : "5594.00",
                           risk:  ex.id == .moex ? 2 : 1)
        DemoDrafts.saveAveraging(env, ex: ex, symbol: ex.heroSymbol,
                                 legEntry: ex.id == .moex ? "92500" : "5600.00",
                                 legLots: "1",
                                 newEntry: ex.id == .moex ? "91500" : "5588.00",
                                 stop:     ex.id == .moex ? "91000" : "5580.00",
                                 risk:     ex.id == .moex ? 2 : 1)
    }
}

@MainActor
enum VideoSeed {
    static func populate(_ env: AppEnvironment, showcase ex: DemoExchange) {
        env.selectedExchange = ex.id
        let main = seedDeposits(env, ex)
        env.selectedDepositID = main

        // Start with a couple of instruments; the hero is added live from search.
        for symbol in ex.videoStartSymbols {
            guard let inst = ex.instruments.first(where: { $0.symbol == symbol }) else { continue }
            try! env.watchlist.add(
                exchangeIDRaw: ex.id.rawValue, family: inst.family,
                activeSymbol: inst.symbol, displayName: inst.name,
                activeExpiration: ex.expiration, iconURLString: nil)
        }
        // No calc draft: the video types entry/stop live. The hero's spec is
        // served by the stub adapter when the calc screen loads.
    }
}

/// Insert the showcase's deposits; returns the id of the first (main) deposit.
@MainActor
private func seedDeposits(_ env: AppEnvironment, _ ex: DemoExchange) -> UUID {
    var mainID: UUID?
    for dep in ex.deposits {
        let entity = try! env.deposits.add(
            name: dep.name, exchangeIDRaw: ex.id.rawValue,
            balance: dep.balance, currencyCode: ex.currency, riskPercent: dep.risk)
        if mainID == nil { mainID = entity.id }
    }
    return mainID!
}

@MainActor
enum DemoDrafts {
    static func saveLot(_ env: AppEnvironment, ex: DemoExchange, symbol: String,
                        entry: String, stop: String, risk: Decimal) {
        let draft = LotCalcDraft(isLong: true, entryText: entry, stopText: stop,
                                 risk: .preset(risk), customRiskText: "")
        if let data = try? JSONEncoder().encode(draft) {
            try? env.calcDrafts.save(exchangeIDRaw: ex.id.rawValue, symbol: symbol,
                                     kindRaw: CalcKind.lot.rawValue, payload: data)
        }
    }

    static func saveAveraging(_ env: AppEnvironment, ex: DemoExchange, symbol: String,
                              legEntry: String, legLots: String,
                              newEntry: String, stop: String, risk: Decimal) {
        let draft = AveragingCalcDraft(
            isLong: true,
            legs: [AveragingLegDraft(entryText: legEntry, lotsText: legLots)],
            newEntryText: newEntry, stopText: stop,
            risk: .preset(risk), customRiskText: "")
        if let data = try? JSONEncoder().encode(draft) {
            try? env.calcDrafts.save(exchangeIDRaw: ex.id.rawValue, symbol: symbol,
                                     kindRaw: CalcKind.averaging.rawValue, payload: data)
        }
    }
}
