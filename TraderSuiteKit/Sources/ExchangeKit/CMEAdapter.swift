import Foundation
import Core

/// CME Group adapter (CME, NYMEX, COMEX, CBOT).
///
/// `fetchInstruments()` generates active contracts locally from the CME
/// rulebook — no network call required, so it never returns 404.
///
/// `fetchSpec(symbol:)` uses hard-coded tick specs (immutable per CME rulebook)
/// and attempts to fetch the current initial margin live; on failure it falls
/// back to the approximate value stored in `CMEParsing.products`.
public struct CMEAdapter: ExchangeAdapter {
    public let exchangeID: ExchangeID = .cme
    private let client: CMEClient

    public init(client: CMEClient = CMEClient()) {
        self.client = client
    }

    // MARK: ExchangeAdapter

    public func fetchInstruments() async throws -> [InstrumentSummary] {
        CMEParsing.generateActiveContracts(asOf: Date())
    }

    public func fetchSpec(symbol: String) async throws -> ContractSpec {
        guard let code = CMEParsing.productCode(fromSymbol: symbol) else {
            throw ExchangeError.instrumentNotFound(symbol)
        }
        let margin = try? await liveMargin(productCode: code)
        return try CMEParsing.parseSpec(symbol: symbol, margin: margin)
    }

    public func resolveFrontContract(family: String) async throws -> ContractSpec {
        let front = try await frontInstrument(family: family)
        return try await fetchSpec(symbol: front.symbol)
    }

    // MARK: Private

    private func liveMargin(productCode: String) async throws -> Decimal {
        let doc = try await client.fetchMargins(productCode: productCode)
        guard let m = CMEParsing.parseMargin(doc, productCode: productCode) else {
            throw ExchangeError.decoding("No margin for \(productCode)")
        }
        return m
    }
}
