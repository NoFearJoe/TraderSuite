import Foundation
import Core

/// MOEX adapter over the public ISS API (`iss.moex.com/iss`, FORTS market).
///
/// Field mapping (verified against the FORTS `securities` block):
///   symbol             <- SECID
///   family             <- ASSETCODE
///   minStep            <- MINSTEP
///   stepPrice          <- STEPPRICE
///   initialMargin (ГО) <- INITIALMARGIN
///   exchangeFeePerSide <- BUYSELLFEE
///   expiration         <- LASTTRADEDATE
public struct MoexAdapter: ExchangeAdapter {
    public let exchangeID: ExchangeID = .moex
    private let client: ISSClient

    public init(client: ISSClient = ISSClient()) {
        self.client = client
    }

    public func fetchInstruments() async throws -> [InstrumentSummary] {
        let document = try await client.fetchDocument(
            path: "engines/futures/markets/forts/securities.json",
            query: [
                URLQueryItem(name: "iss.meta", value: "off"),
                URLQueryItem(name: "iss.only", value: "securities"),
                URLQueryItem(
                    name: "securities.columns",
                    value: "SECID,SHORTNAME,ASSETCODE,LASTTRADEDATE,SECTYPE"
                ),
            ]
        )
        return MoexParsing.parseInstruments(document)
    }

    public func fetchSpec(symbol: String) async throws -> ContractSpec {
        let document = try await client.fetchDocument(
            path: "engines/futures/markets/forts/securities/\(symbol).json",
            query: [URLQueryItem(name: "iss.meta", value: "off")]
        )
        return try MoexParsing.parseSpec(document, symbol: symbol)
    }

    public func resolveFrontContract(family: String) async throws -> ContractSpec {
        let front = try await frontInstrument(family: family)
        return try await fetchSpec(symbol: front.symbol)
    }
}
