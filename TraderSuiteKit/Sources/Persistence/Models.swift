import Foundation
import SwiftData

// NOTE on CloudKit (Phase 3): to sync via CloudKit every stored property must
// have a default value, there can be no `.unique` attribute, and relationships
// must be optional. The models below already follow these rules so enabling
// sync later is just a configuration + entitlement change.

/// A trading deposit, tied to one exchange. The user may have several.
@Model
public final class DepositEntity {
    public var id: UUID = UUID()
    public var name: String = ""
    public var exchangeIDRaw: String = ""      // ExchangeID.rawValue
    public var balance: Decimal = 0
    public var currencyCode: String = ""
    public var riskPercent: Decimal = 0.02     // default per-trade risk
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        name: String = "",
        exchangeIDRaw: String = "",
        balance: Decimal = 0,
        currencyCode: String = "",
        riskPercent: Decimal = 0.02,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.exchangeIDRaw = exchangeIDRaw
        self.balance = balance
        self.currencyCode = currencyCode
        self.riskPercent = riskPercent
        self.createdAt = createdAt
    }
}

/// A watchlist tracks an instrument *family* (e.g. "Si") and the currently active
/// front contract, so it can be rolled forward automatically after expiration.
@Model
public final class WatchlistEntity {
    public var id: UUID = UUID()
    public var exchangeIDRaw: String = ""
    public var family: String = ""
    public var activeSymbol: String = ""
    public var displayName: String = ""
    /// Expiration of the active contract; drives "expiring soon" + auto-rollover.
    /// Optional (CloudKit-safe) and unknown until the front contract is resolved.
    public var activeExpiration: Date?
    /// Instrument artwork supplied by the exchange, if any (stored as a string for
    /// CloudKit-safety). `nil` when the exchange has no icon — the UI shows none.
    public var iconURLString: String?
    public var createdAt: Date = Date()
    /// Whether the user wants a local notification for this instrument's expiration.
    public var notificationEnabled: Bool = false
    /// Days before expiration to fire the reminder (0 = day of, max 7).
    public var notificationLeadDays: Int = 1
    /// User-defined position in the watchlist (drag-to-reorder). Lower sorts first;
    /// ties fall back to `createdAt` (newest first). Defaults to 0 so pre-existing
    /// rows keep their original newest-first order until the user reorders.
    public var sortOrder: Int = 0

    public init(
        id: UUID = UUID(),
        exchangeIDRaw: String = "",
        family: String = "",
        activeSymbol: String = "",
        displayName: String = "",
        activeExpiration: Date? = nil,
        iconURLString: String? = nil,
        createdAt: Date = Date(),
        notificationEnabled: Bool = false,
        notificationLeadDays: Int = 1,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.exchangeIDRaw = exchangeIDRaw
        self.family = family
        self.activeSymbol = activeSymbol
        self.displayName = displayName
        self.activeExpiration = activeExpiration
        self.iconURLString = iconURLString
        self.createdAt = createdAt
        self.notificationEnabled = notificationEnabled
        self.notificationLeadDays = notificationLeadDays
        self.sortOrder = sortOrder
    }
}

/// A saved draft of a calculator's input fields for one instrument, so the screen
/// can pre-fill the user's previous parameters when they return. One row per
/// (exchange, symbol, calculator kind). The `payload` is an opaque `Codable` blob
/// owned by the `Features` layer — `Persistence` stays agnostic of its shape.
@Model
public final class CalcDraftEntity {
    public var exchangeIDRaw: String = ""
    public var symbol: String = ""
    /// Discriminates the calculator the draft belongs to (e.g. "lot", "averaging").
    public var kindRaw: String = ""
    /// Feature-owned, JSON-encoded snapshot of the input fields.
    public var payload: Data = Data()
    public var updatedAt: Date = Date()

    public init(
        exchangeIDRaw: String = "",
        symbol: String = "",
        kindRaw: String = "",
        payload: Data = Data(),
        updatedAt: Date = Date()
    ) {
        self.exchangeIDRaw = exchangeIDRaw
        self.symbol = symbol
        self.kindRaw = kindRaw
        self.payload = payload
        self.updatedAt = updatedAt
    }
}

/// Cached contract specification fetched from an exchange adapter.
@Model
public final class CachedSpecEntity {
    public var symbol: String = ""
    public var exchangeIDRaw: String = ""
    public var minStep: Decimal = 0
    public var stepPrice: Decimal = 0
    public var initialMargin: Decimal = 0
    public var exchangeFeePerSide: Decimal = 0
    public var isPerpetual: Bool = false
    public var expiration: Date?               // nil for perpetual
    public var updatedAt: Date = Date()

    public init(
        symbol: String = "",
        exchangeIDRaw: String = "",
        minStep: Decimal = 0,
        stepPrice: Decimal = 0,
        initialMargin: Decimal = 0,
        exchangeFeePerSide: Decimal = 0,
        isPerpetual: Bool = false,
        expiration: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.symbol = symbol
        self.exchangeIDRaw = exchangeIDRaw
        self.minStep = minStep
        self.stepPrice = stepPrice
        self.initialMargin = initialMargin
        self.exchangeFeePerSide = exchangeFeePerSide
        self.isPerpetual = isPerpetual
        self.expiration = expiration
        self.updatedAt = updatedAt
    }
}
