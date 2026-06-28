import Foundation

/// The subset of a futures contract specification needed for sizing math.
/// Populated from an exchange adapter (e.g. MOEX ISS API) and cached.
public struct ContractSpec: Sendable, Hashable {
    /// Instrument symbol, e.g. "Si-3.25".
    public let symbol: String
    /// Minimum price increment, in price points (MOEX: MINSTEP).
    public let minStep: Decimal
    /// Currency value of one `minStep` (MOEX: STEPPRICE), in exchange currency.
    public let stepPrice: Decimal
    /// Initial margin / guarantee (ГО) required per contract, in exchange currency.
    public let initialMargin: Decimal
    /// Exchange commission per contract, per side, in exchange currency.
    public let exchangeFeePerSide: Decimal

    public init(
        symbol: String,
        minStep: Decimal,
        stepPrice: Decimal,
        initialMargin: Decimal,
        exchangeFeePerSide: Decimal = 0
    ) {
        self.symbol = symbol
        self.minStep = minStep
        self.stepPrice = stepPrice
        self.initialMargin = initialMargin
        self.exchangeFeePerSide = exchangeFeePerSide
    }
}
