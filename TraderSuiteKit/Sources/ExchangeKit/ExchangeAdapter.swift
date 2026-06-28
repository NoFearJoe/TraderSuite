import Foundation
import Core

public enum ExchangeError: Error, Sendable, Equatable {
    case notImplemented
    case network(String)
    case decoding(String)
    case instrumentNotFound(String)
}

/// The seam every exchange integration must implement.
/// Phase 2 adds the concrete MOEX implementation over the ISS API.
public protocol ExchangeAdapter: Sendable {
    var exchangeID: ExchangeID { get }

    /// List instruments available to trade on this exchange.
    func fetchInstruments() async throws -> [InstrumentSummary]

    /// Numeric specification (tick size, step price, margin, fees) for one symbol.
    func fetchSpec(symbol: String) async throws -> ContractSpec

    /// Current front (non-expired) contract for an instrument family — used to
    /// roll a watchlist forward after expiration. Throws for perpetual families.
    func resolveFrontContract(family: String) async throws -> ContractSpec
}
