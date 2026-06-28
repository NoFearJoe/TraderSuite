import Foundation
import Observation
import SwiftData
import ExchangeKit
import Persistence

/// Composition root shared across screens: the persistence stores, the
/// cache-first `SpecProvider`, the exchange registry, and the currently active
/// deposit. Created once from the app's `ModelContainer` and injected into the
/// SwiftUI environment.
///
/// `@MainActor` because it owns the `@MainActor` stores.
@MainActor
@Observable
public final class AppEnvironment {
    public let deposits: DepositStore
    public let watchlist: WatchlistStore
    public let calcDrafts: CalcDraftStore
    public let specCache: SpecCache
    public let specProvider: SpecProvider
    public let registry: ExchangeRegistry
    public let notificationScheduler: NotificationScheduling

    /// Live subscription entitlement, backed by StoreKit 2 transactions.
    public let subscriptions = SubscriptionStore()

    // MARK: - Persisted selection (UserDefaults)

    // Backing stores — @ObservationIgnored so the macro doesn't expand them.
    // The computed properties below manage observation manually via access/withMutation.
    @ObservationIgnored private var _selectedExchange: ExchangeID
    @ObservationIgnored private var _selectedDepositID: UUID?
    /// Per-exchange last-selected deposit: [ExchangeID.rawValue: UUID.uuidString]
    @ObservationIgnored private var _depositIDsByExchange: [String: String]

    /// The exchange the home screen is currently showing. Persisted in UserDefaults.
    /// Setting it automatically restores the deposit last selected for that exchange.
    public var selectedExchange: ExchangeID {
        get {
            access(keyPath: \.selectedExchange)
            return _selectedExchange
        }
        set {
            withMutation(keyPath: \.selectedExchange) {
                _selectedExchange = newValue
            }
            UserDefaults.standard.set(newValue.rawValue, forKey: PrefKey.exchange)
            let restoredID = _depositIDsByExchange[newValue.rawValue]
                .flatMap { UUID(uuidString: $0) }
            withMutation(keyPath: \.selectedDepositID) {
                _selectedDepositID = restoredID
            }
        }
    }

    /// The deposit selected for calculations. Persisted per-exchange in UserDefaults.
    public var selectedDepositID: UUID? {
        get {
            access(keyPath: \.selectedDepositID)
            return _selectedDepositID
        }
        set {
            withMutation(keyPath: \.selectedDepositID) {
                _selectedDepositID = newValue
            }
            if let newValue {
                _depositIDsByExchange[_selectedExchange.rawValue] = newValue.uuidString
            } else {
                _depositIDsByExchange.removeValue(forKey: _selectedExchange.rawValue)
            }
            UserDefaults.standard.set(_depositIDsByExchange, forKey: PrefKey.depositIDs)
        }
    }

    // MARK: - Init

    public init(
        container: ModelContainer,
        registry: ExchangeRegistry,
        notificationScheduler: NotificationScheduling = UserNotificationScheduler()
    ) {
        let context = container.mainContext
        let cache = SpecCache(context: context)
        self.deposits = DepositStore(context: context)
        self.watchlist = WatchlistStore(context: context)
        self.calcDrafts = CalcDraftStore(context: context)
        self.specCache = cache
        self.specProvider = SpecProvider(cache: cache, registry: registry)
        self.registry = registry
        self.notificationScheduler = notificationScheduler

        // On first launch (no saved value) the default exchange follows the
        // device region: MOEX for Russia, CME everywhere else.
        let savedExchangeRaw = UserDefaults.standard.string(forKey: PrefKey.exchange) ?? ""
        let savedExchange = ExchangeID(rawValue: savedExchangeRaw)
            ?? Self.defaultExchangeForRegion()
        let savedDepositIDs = (UserDefaults.standard.dictionary(forKey: PrefKey.depositIDs)
            as? [String: String]) ?? [:]
        self._selectedExchange = savedExchange
        self._depositIDsByExchange = savedDepositIDs
        self._selectedDepositID = savedDepositIDs[savedExchange.rawValue]
            .flatMap { UUID(uuidString: $0) }
    }

    // MARK: - Helpers

    /// The exchange to preselect on first launch, based on the device region:
    /// MOEX for Russia, EUREX for the euro area, SGX for the Asia-Pacific, CME for
    /// everyone else.
    static func defaultExchangeForRegion() -> ExchangeID {
        let region = Locale.current.region?.identifier ?? ""
        if region == "RU" { return .moex }
        if euroAreaRegions.contains(region) { return .eurex }
        if asiaPacificRegions.contains(region) { return .sgx }
        return .cme
    }

    /// Euro-area (and closely-tied) regions whose traders are nearest to Eurex.
    private static let euroAreaRegions: Set<String> = [
        "DE", "FR", "IT", "ES", "NL", "BE", "AT", "PT", "IE", "FI",
        "GR", "SK", "SI", "LU", "LV", "LT", "EE", "CY", "MT", "CH",
    ]

    /// Asia-Pacific regions whose traders are nearest to SGX's international book.
    private static let asiaPacificRegions: Set<String> = [
        "SG", "MY", "HK", "CN", "ID", "TH", "PH", "VN", "TW", "JP", "KR", "IN", "AU", "NZ",
    ]

    /// The active deposit entity, if one is selected and still exists.
    public func selectedDeposit() -> DepositEntity? {
        guard let id = selectedDepositID else { return nil }
        return (try? deposits.all())?.first { $0.id == id }
    }

    /// The default live registry: MOEX + CME + EUREX + SGX.
    public static func makeDefaultRegistry() -> ExchangeRegistry {
        ExchangeRegistry(adapters: [MoexAdapter(), CMEAdapter(), EurexAdapter(), SGXAdapter()])
    }

    /// An in-memory environment for SwiftUI previews and tests.
    public static func inMemory(
        registry: ExchangeRegistry = ExchangeRegistry()
    ) -> AppEnvironment {
        let container = try! PersistenceContainer.make(inMemory: true)
        return AppEnvironment(
            container: container,
            registry: registry,
            notificationScheduler: NoopNotificationScheduler()
        )
    }
}

// MARK: - UserDefaults keys

private enum PrefKey {
    static let exchange  = "app.selectedExchange"
    static let depositIDs = "app.selectedDepositIDs"
}
