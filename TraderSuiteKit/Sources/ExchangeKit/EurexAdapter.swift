import Foundation
import Core

/// Eurex adapter (European derivatives — equity index + German yield curve).
///
/// Fully offline: both the contract list and the numeric specs come from the
/// static `EurexParsing` catalogue. Unlike CME, Eurex exposes no free per-contract
/// initial-margin endpoint (margins are portfolio based), so margins are the
/// approximate static values in the catalogue and there is no network client.
public struct EurexAdapter: ExchangeAdapter {
    public let exchangeID: ExchangeID = .eurex

    public init() {}

    // MARK: ExchangeAdapter

    public func fetchInstruments() async throws -> [InstrumentSummary] {
        EurexParsing.generateActiveContracts(asOf: Date())
    }

    public func fetchSpec(symbol: String) async throws -> ContractSpec {
        try EurexParsing.parseSpec(symbol: symbol)
    }

    public func resolveFrontContract(family: String) async throws -> ContractSpec {
        let front = try await frontInstrument(family: family)
        return try await fetchSpec(symbol: front.symbol)
    }
}
