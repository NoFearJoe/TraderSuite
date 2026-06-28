import Foundation

/// Supported exchanges. Adding one starts here plus a new `ExchangeAdapter`.
public enum ExchangeID: String, Sendable, Hashable, CaseIterable {
    /// CME Group: CME, CBOT, NYMEX, COMEX.
    case cme
    /// Eurex: the European derivatives exchange (Frankfurt).
    case eurex
    /// Russian exchange
    case moex
    /// SGX: Singapore Exchange — pan-Asian international futures (USD settled).
    case sgx

    /// ISO-ish currency the exchange settles in (used for deposits & display).
    public var currencyCode: String {
        switch self {
        case .moex:  return "RUB"
        case .cme:   return "USD"
        case .eurex: return "EUR"
        case .sgx:   return "USD"
        }
    }

    public var displayName: String {
        switch self {
        case .moex:  return "MOEX"
        case .cme:   return "CME"
        case .eurex: return "EUREX"
        case .sgx:   return "SGX"
        }
    }

    /// Emoji flag of the exchange's home country, for compact display.
    public var flag: String {
        switch self {
        case .moex:  return "🇷🇺"
        case .cme:   return "🇺🇸"
        case .eurex: return "🇪🇺"
        case .sgx:   return "🇸🇬"
        }
    }
}

/// Lightweight description of a tradable instrument, returned when listing.
/// Full numeric specs are fetched separately as `ContractSpec`.
public struct InstrumentSummary: Sendable, Hashable {
    public let symbol: String       // e.g. "Si-3.25"
    public let family: String       // e.g. "Si" — what a watchlist tracks across rollovers
    public let displayName: String
    public let isPerpetual: Bool
    public let expiration: Date?    // nil for perpetual contracts
    /// Artwork for the instrument, when the exchange supplies one. `nil` when the
    /// exchange has no icon (e.g. MOEX ISS) — callers then show no icon.
    public let iconURL: URL?

    public init(
        symbol: String,
        family: String,
        displayName: String,
        isPerpetual: Bool,
        expiration: Date?,
        iconURL: URL? = nil
    ) {
        self.symbol = symbol
        self.family = family
        self.displayName = displayName
        self.isPerpetual = isPerpetual
        self.expiration = expiration
        self.iconURL = iconURL
    }
}
