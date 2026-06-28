import Testing
import Foundation
import Core
@testable import ExchangeKit

@Suite("CME parsing")
struct CMEParsingTests {

    // MARK: - Product code extraction

    @Test("Extracts product code from 2-digit year symbol")
    func extractsProductCode2Digit() {
        #expect(CMEParsing.productCode(fromSymbol: "ESH26") == "ES")
        #expect(CMEParsing.productCode(fromSymbol: "NQU26") == "NQ")
        #expect(CMEParsing.productCode(fromSymbol: "CLZ25") == "CL")
        #expect(CMEParsing.productCode(fromSymbol: "GCQ26") == "GC")
        #expect(CMEParsing.productCode(fromSymbol: "6EU26") == "6E")
        #expect(CMEParsing.productCode(fromSymbol: "RTYH26") == "RTY")
        #expect(CMEParsing.productCode(fromSymbol: "ZBZ26") == "ZB")
        #expect(CMEParsing.productCode(fromSymbol: "MESH26") == "MES")
    }

    @Test("Returns nil for unrecognised symbol format")
    func returnsNilForBadSymbol() {
        #expect(CMEParsing.productCode(fromSymbol: "XX") == nil)
        #expect(CMEParsing.productCode(fromSymbol: "") == nil)
    }

    // MARK: - parseSpec

    @Test("Builds ContractSpec from static database")
    func buildsSpecFromDatabase() throws {
        let spec = try CMEParsing.parseSpec(symbol: "ESH26")
        #expect(spec.symbol == "ESH26")
        #expect(spec.minStep == 0.25)
        #expect(spec.stepPrice == 12.5)
        #expect(spec.exchangeFeePerSide == 1.45)
        #expect(spec.initialMargin == 15600)
    }

    @Test("Margin override is respected")
    func marginOverride() throws {
        let spec = try CMEParsing.parseSpec(symbol: "ESH26", margin: 17000)
        #expect(spec.initialMargin == 17000)
    }

    @Test("Unknown symbol throws instrumentNotFound")
    func unknownSymbolThrows() {
        #expect(throws: ExchangeError.self) {
            _ = try CMEParsing.parseSpec(symbol: "XYZH26")
        }
    }

    // MARK: - Date parsing

    @Test("Parses ISO date")
    func parsesISODate() {
        #expect(CMEParsing.parseExpDate("2026-09-18") != nil)
    }

    @Test("Parses US slash date")
    func parsesUSDate() {
        #expect(CMEParsing.parseExpDate("09/18/2026") != nil)
    }

    @Test("Parses US short slash date")
    func parsesUSShortDate() {
        #expect(CMEParsing.parseExpDate("09/18/26") != nil)
    }

    @Test("Returns nil for bad date string")
    func returnsNilForBadDate() {
        #expect(CMEParsing.parseExpDate("not-a-date") == nil)
    }

    // MARK: - Expiration date calculation

    /// ES March 2026: third Friday of March = March 20, 2026.
    @Test("thirdFriday — ES March 2026 is March 20")
    func thirdFridayMarch2026() {
        let date = CMEParsing.expirationDate(rule: .thirdFriday, monthCode: "H", year: 2026)
        let expected = CMEParsing.parseExpDate("2026-03-20")
        #expect(date == expected)
    }

    /// ES June 2026: third Friday of June = June 19, 2026.
    @Test("thirdFriday — ES June 2026 is June 19")
    func thirdFridayJune2026() {
        let date = CMEParsing.expirationDate(rule: .thirdFriday, monthCode: "M", year: 2026)
        let expected = CMEParsing.parseExpDate("2026-06-19")
        #expect(date == expected)
    }

    /// FX March 2026: third Wednesday = March 18, minus 2 weekdays = March 16.
    @Test("twoBeforeThirdWednesday — 6E March 2026 is March 16")
    func twoBeforeThirdWednesdayMarch2026() {
        let date = CMEParsing.expirationDate(rule: .twoBeforeThirdWednesday, monthCode: "H", year: 2026)
        let expected = CMEParsing.parseExpDate("2026-03-16")
        #expect(date == expected)
    }

    /// CL March 2026: 3 weekdays before Feb 25. Feb 25 is Wednesday → minus 3 = Feb 20 (Friday).
    @Test("thirdBeforeTwentyFifthPrior — CL March 2026 is Feb 20")
    func thirdBeforeTwentyFifthPriorMarch2026() {
        let date = CMEParsing.expirationDate(rule: .thirdBeforeTwentyFifthPrior, monthCode: "H", year: 2026)
        let expected = CMEParsing.parseExpDate("2026-02-20")
        #expect(date == expected)
    }

    /// NG March 2026: 3 weekdays before March 1 (Sunday). Prior weekday = Feb 27 (Fri), minus 2 more = Feb 25 (Wed).
    @Test("threeBeforeFirstOfMonth — NG March 2026 is Feb 25")
    func threeBeforeFirstOfMonthMarch2026() {
        let date = CMEParsing.expirationDate(rule: .threeBeforeFirstOfMonth, monthCode: "H", year: 2026)
        let expected = CMEParsing.parseExpDate("2026-02-25")
        #expect(date == expected)
    }

    // MARK: - Static contract generation

    @Test("generateActiveContracts returns non-empty list")
    func generatesContracts() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let contracts = CMEParsing.generateActiveContracts(asOf: ref)
        #expect(!contracts.isEmpty)
    }

    @Test("All generated contracts have a future expiration")
    func allContractsAreFuture() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let contracts = CMEParsing.generateActiveContracts(asOf: ref)
        #expect(contracts.allSatisfy { ($0.expiration ?? .distantFuture) >= ref })
    }

    @Test("Each contract family is covered")
    func allFamiliesCovered() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let families = Set(CMEParsing.generateActiveContracts(asOf: ref).map { $0.family })
        for code in CMEParsing.supportedCodes {
            #expect(families.contains(code), "\(code) missing from generated contracts")
        }
    }

    @Test("Quarterly products produce 8 contracts")
    func quarterlyProductsHave8Contracts() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let es = CMEParsing.generateActiveContracts(asOf: ref).filter { $0.family == "ES" }
        #expect(es.count == 8)
        // All ES symbols must carry the H/M/U/Z month code
        let quarterCodes: Set<Character> = ["H","M","U","Z"]
        #expect(es.allSatisfy { quarterCodes.contains($0.symbol.dropFirst(2).first ?? "?") })
    }

    @Test("Monthly products produce 18 contracts")
    func monthlyProductsHave18Contracts() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let cl = CMEParsing.generateActiveContracts(asOf: ref).filter { $0.family == "CL" }
        #expect(cl.count == 18)
    }

    @Test("Contracts are sorted by expiration date")
    func contractsAreSorted() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let contracts = CMEParsing.generateActiveContracts(asOf: ref)
        let dates = contracts.compactMap { $0.expiration }
        #expect(dates == dates.sorted())
    }

    @Test("Generated symbol format is correct")
    func symbolFormatIsCorrect() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let es = CMEParsing.generateActiveContracts(asOf: ref).first { $0.family == "ES" }
        #expect(es != nil)
        // Symbol must start with "ES", followed by a month code, then 2 digits
        let sym = es!.symbol
        #expect(sym.hasPrefix("ES"))
        #expect(sym.count == 5)  // ES + monthCode(1) + year(2)
    }

    // MARK: - Front contract

    @Test("Front contract is the nearest non-expired one")
    func frontContractSelection() {
        let ref = CMEParsing.parseExpDate("2026-01-01")!
        let contracts = CMEParsing.generateActiveContracts(asOf: ref).filter { $0.family == "ES" }
        let front = InstrumentSelection.frontContract(contracts, family: "ES", now: ref)
        #expect(front != nil)
        // The front contract must expire on or after ref
        #expect((front?.expiration ?? .distantFuture) >= ref)
        // It must be the earliest of all ES contracts
        let earliestExp = contracts.compactMap { $0.expiration }.min()
        #expect(front?.expiration == earliestExp)
    }
}
