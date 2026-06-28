import Testing
import Foundation
import Core
@testable import ExchangeKit

@Suite("Eurex parsing")
struct EurexParsingTests {

    /// Build a reference date in the Eurex calendar (Europe/Berlin).
    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Product code extraction

    @Test("Extracts product code from symbol")
    func extractsProductCode() {
        #expect(EurexParsing.productCode(fromSymbol: "FESXH26") == "FESX")
        #expect(EurexParsing.productCode(fromSymbol: "FDAXM26") == "FDAX")
        #expect(EurexParsing.productCode(fromSymbol: "FDXSU26") == "FDXS")
        #expect(EurexParsing.productCode(fromSymbol: "FGBLZ26") == "FGBL")
        // FGBM ends in "M" (a month code) — only ONE month letter is stripped.
        #expect(EurexParsing.productCode(fromSymbol: "FGBMH26") == "FGBM")
        #expect(EurexParsing.productCode(fromSymbol: "FGBSZ25") == "FGBS")
    }

    @Test("Returns nil for unrecognised symbol format")
    func returnsNilForBadSymbol() {
        #expect(EurexParsing.productCode(fromSymbol: "XX") == nil)
        #expect(EurexParsing.productCode(fromSymbol: "") == nil)
    }

    // MARK: - parseSpec

    @Test("Builds ContractSpec from static database")
    func buildsSpecFromDatabase() throws {
        let spec = try EurexParsing.parseSpec(symbol: "FESXH26")
        #expect(spec.symbol == "FESXH26")
        #expect(spec.minStep == 1.0)
        #expect(spec.stepPrice == 10.0)
        #expect(spec.exchangeFeePerSide == 0.50)
        #expect(spec.initialMargin == 3500)
    }

    @Test("Unknown symbol throws instrumentNotFound")
    func unknownSymbolThrows() {
        #expect(throws: ExchangeError.self) {
            _ = try EurexParsing.parseSpec(symbol: "FXYZH26")
        }
    }

    // MARK: - Expiration date calculation

    /// FESX March 2026: third Friday of March = March 20, 2026.
    @Test("thirdFriday — FESX March 2026 is March 20")
    func thirdFridayMarch2026() {
        let d = EurexParsing.expirationDate(rule: .thirdFriday, monthCode: "H", year: 2026)
        #expect(d == Self.date(2026, 3, 20))
    }

    /// FESX June 2026: third Friday of June = June 19, 2026.
    @Test("thirdFriday — FESX June 2026 is June 19")
    func thirdFridayJune2026() {
        let d = EurexParsing.expirationDate(rule: .thirdFriday, monthCode: "M", year: 2026)
        #expect(d == Self.date(2026, 6, 19))
    }

    /// FGBL March 2026: the 10th is Tuesday (a weekday), minus 2 weekdays = March 6 (Friday).
    @Test("twoBeforeTenth — FGBL March 2026 is March 6")
    func twoBeforeTenthMarch2026() {
        let d = EurexParsing.expirationDate(rule: .twoBeforeTenth, monthCode: "H", year: 2026)
        #expect(d == Self.date(2026, 3, 6))
    }

    /// FGBL Sep 2026: Sep 10 is a Saturday → rolls forward to Mon Sep 12; going
    /// back 2 weekdays skips Sun 11 and Sat 10, counts Fri 9 then Thu 8 → Sep 8.
    @Test("twoBeforeTenth — FGBL Sep 2026 is Sep 8")
    func twoBeforeTenthSep2026() {
        let d = EurexParsing.expirationDate(rule: .twoBeforeTenth, monthCode: "U", year: 2026)
        #expect(d == Self.date(2026, 9, 8))
    }

    // MARK: - Static contract generation

    @Test("generateActiveContracts returns a non-empty list")
    func generatesContracts() {
        let contracts = EurexParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1))
        #expect(!contracts.isEmpty)
    }

    @Test("All generated contracts have a future expiration")
    func allContractsAreFuture() {
        let ref = Self.date(2026, 1, 1)
        let contracts = EurexParsing.generateActiveContracts(asOf: ref)
        #expect(contracts.allSatisfy { ($0.expiration ?? .distantFuture) >= ref })
    }

    @Test("Each supported family is covered")
    func allFamiliesCovered() {
        let families = Set(EurexParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)).map { $0.family })
        for code in EurexParsing.supportedCodes {
            #expect(families.contains(code), "\(code) missing from generated contracts")
        }
    }

    @Test("Each product generates 8 quarterly contracts")
    func eightQuarterlyContracts() {
        let ref = Self.date(2026, 1, 1)
        let fesx = EurexParsing.generateActiveContracts(asOf: ref).filter { $0.family == "FESX" }
        #expect(fesx.count == 8)
        // Every symbol carries a quarterly month code H/M/U/Z right after "FESX".
        let quarterCodes: Set<Character> = ["H", "M", "U", "Z"]
        #expect(fesx.allSatisfy { quarterCodes.contains($0.symbol.dropFirst(4).first ?? "?") })
    }

    @Test("Contracts are sorted by expiration date")
    func contractsAreSorted() {
        let dates = EurexParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)).compactMap { $0.expiration }
        #expect(dates == dates.sorted())
    }

    @Test("Generated symbol round-trips through productCode")
    func symbolRoundTrips() {
        let contracts = EurexParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1))
        for c in contracts {
            #expect(EurexParsing.productCode(fromSymbol: c.symbol) == c.family)
        }
    }

    // MARK: - Front contract

    @Test("Front contract is the nearest non-expired one")
    func frontContractSelection() {
        let ref = Self.date(2026, 1, 1)
        let fesx = EurexParsing.generateActiveContracts(asOf: ref).filter { $0.family == "FESX" }
        let front = InstrumentSelection.frontContract(fesx, family: "FESX", now: ref)
        #expect(front != nil)
        #expect(front?.expiration == fesx.compactMap { $0.expiration }.min())
    }
}
