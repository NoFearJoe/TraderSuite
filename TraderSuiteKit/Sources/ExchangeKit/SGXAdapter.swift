import Foundation
import Core

/// SGX adapter (Singapore Exchange — pan-Asian international index + commodity
/// futures: FTSE China A50, USD Nikkei 225, Iron Ore 62% Fe).
///
/// Fully offline like `EurexAdapter`: both the contract list and the numeric
/// specs come from the static `SGXParsing` catalogue. SGX exposes no free
/// per-contract margin endpoint, so margins are the approximate static values in
/// the catalogue and there is no network client.
public struct SGXAdapter: ExchangeAdapter {
    public let exchangeID: ExchangeID = .sgx

    public init() {}

    // MARK: ExchangeAdapter

    public func fetchInstruments() async throws -> [InstrumentSummary] {
        SGXParsing.generateActiveContracts(asOf: Date())
    }

    public func fetchSpec(symbol: String) async throws -> ContractSpec {
        try SGXParsing.parseSpec(symbol: symbol)
    }

    public func resolveFrontContract(family: String) async throws -> ContractSpec {
        let front = try await frontInstrument(family: family)
        return try await fetchSpec(symbol: front.symbol)
    }
}
