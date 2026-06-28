import Foundation
import Core

/// Pure functions that map ISS documents to domain types.
/// No networking here, so this is fully unit-testable with sample payloads.
enum MoexParsing {

    /// ISS column names (verified against the FORTS `securities` block).
    enum Col {
        static let secid = "SECID"
        static let shortName = "SHORTNAME"
        static let assetCode = "ASSETCODE"        // instrument family, e.g. "Si"
        static let lastTradeDate = "LASTTRADEDATE"
        static let minStep = "MINSTEP"
        static let stepPrice = "STEPPRICE"
        static let initialMargin = "INITIALMARGIN" // ГО
        static let buySellFee = "BUYSELLFEE"       // exchange fee per trade (per side)
    }

    /// Parses "YYYY-MM-DD" as a Moscow-time date (no DateFormatter -> Sendable-safe).
    static func parseDate(_ string: String) -> Date? {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let moscow = TimeZone(identifier: "Europe/Moscow") else { return nil }
        calendar.timeZone = moscow
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    static func parseInstruments(_ document: ISSDocument) -> [InstrumentSummary] {
        guard let block = document["securities"] else { return [] }
        return block.rows().compactMap { row in
            guard let secid = row[Col.secid]?.stringValue, !secid.isEmpty else { return nil }
            let family = row[Col.assetCode]?.stringValue ?? secid
            let name = row[Col.shortName]?.stringValue ?? secid
            let expiration = row[Col.lastTradeDate]?.stringValue.flatMap(parseDate)
            return InstrumentSummary(
                symbol: secid,
                family: family,
                displayName: name,
                isPerpetual: false,          // all MOEX FORTS contracts are dated
                expiration: expiration
            )
        }
    }

    static func parseSpec(_ document: ISSDocument, symbol: String) throws -> ContractSpec {
        // INITIALMARGIN / STEPPRICE live in `securities`; merge with `marketdata`
        // defensively in case a field moves between blocks.
        var merged: [String: ISSValue] = [:]
        for blockName in ["securities", "marketdata"] {
            guard let block = document[blockName] else { continue }
            for row in block.rows() {
                let rowSecid = row[Col.secid]?.stringValue
                guard rowSecid == nil || rowSecid == symbol else { continue }
                for (key, value) in row where value != .null {
                    merged[key] = value
                }
            }
        }

        guard let minStep = merged[Col.minStep]?.decimalValue,
              let stepPrice = merged[Col.stepPrice]?.decimalValue else {
            throw ExchangeError.decoding("Missing MINSTEP/STEPPRICE for \(symbol)")
        }

        return ContractSpec(
            symbol: symbol,
            minStep: minStep,
            stepPrice: stepPrice,
            initialMargin: merged[Col.initialMargin]?.decimalValue ?? 0,
            exchangeFeePerSide: merged[Col.buySellFee]?.decimalValue ?? 0
        )
    }

    /// Nearest non-expired contract for a family — the rollover target.
    /// Delegates to the exchange-agnostic `InstrumentSelection`.
    static func frontContract(
        _ instruments: [InstrumentSummary],
        family: String,
        now: Date
    ) -> InstrumentSummary? {
        InstrumentSelection.frontContract(instruments, family: family, now: now)
    }
}
