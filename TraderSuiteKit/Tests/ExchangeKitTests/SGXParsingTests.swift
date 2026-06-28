import Testing
import Foundation
import Core
@testable import ExchangeKit

@Suite("SGX parsing")
struct SGXParsingTests {

    /// Build a reference date in the SGX calendar (Asia/Singapore).
    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - Product code extraction

    @Test("Extracts product code from symbol")
    func extractsProductCode() {
        #expect(SGXParsing.productCode(fromSymbol: "CNF26") == "CN")
        #expect(SGXParsing.productCode(fromSymbol: "NKH26") == "NK")
        #expect(SGXParsing.productCode(fromSymbol: "NKM26") == "NK")
        // FEF ends in "F" (a month code) — only ONE month letter is stripped.
        #expect(SGXParsing.productCode(fromSymbol: "FEFF26") == "FEF")
        #expect(SGXParsing.productCode(fromSymbol: "FEFM26") == "FEF")
    }

    @Test("Returns nil for unrecognised symbol format")
    func returnsNilForBadSymbol() {
        #expect(SGXParsing.productCode(fromSymbol: "X") == nil)
        #expect(SGXParsing.productCode(fromSymbol: "") == nil)
    }

    // MARK: - parseSpec

    @Test("Builds ContractSpec from static database")
    func buildsSpecFromDatabase() throws {
        let spec = try SGXParsing.parseSpec(symbol: "CNF26")
        #expect(spec.symbol == "CNF26")
        #expect(spec.minStep == 2.5)
        #expect(spec.stepPrice == 2.5)
        #expect(spec.exchangeFeePerSide == 0.50)
        #expect(spec.initialMargin == 1500)
    }

    @Test("Unknown symbol throws instrumentNotFound")
    func unknownSymbolThrows() {
        #expect(throws: ExchangeError.self) {
            _ = try SGXParsing.parseSpec(symbol: "ZZF26")
        }
    }

    // MARK: - Expiration date calculation

    /// FTSE China A50, March 2026: month ends Tue Mar 31 (last biz day); the
    /// second-last business day is Mon Mar 30.
    @Test("secondLastBusinessDay — CN March 2026 is March 30")
    func secondLastBusinessDayMarch2026() {
        let d = SGXParsing.expirationDate(rule: .secondLastBusinessDay, monthCode: "H", year: 2026)
        #expect(d == Self.date(2026, 3, 30))
    }

    /// Iron Ore, March 2026: last business day = Tue Mar 31.
    @Test("lastBusinessDay — FEF March 2026 is March 31")
    func lastBusinessDayMarch2026() {
        let d = SGXParsing.expirationDate(rule: .lastBusinessDay, monthCode: "H", year: 2026)
        #expect(d == Self.date(2026, 3, 31))
    }

    /// Nikkei, March 2026: second Friday = Mar 13, the day before is Thu Mar 12.
    @Test("dayBeforeSecondFriday — NK March 2026 is March 12")
    func dayBeforeSecondFridayMarch2026() {
        let d = SGXParsing.expirationDate(rule: .dayBeforeSecondFriday, monthCode: "H", year: 2026)
        #expect(d == Self.date(2026, 3, 12))
    }

    /// Nikkei, June 2026: second Friday = Jun 12, the day before is Thu Jun 11.
    @Test("dayBeforeSecondFriday — NK June 2026 is June 11")
    func dayBeforeSecondFridayJune2026() {
        let d = SGXParsing.expirationDate(rule: .dayBeforeSecondFriday, monthCode: "M", year: 2026)
        #expect(d == Self.date(2026, 6, 11))
    }

    // MARK: - Static contract generation

    @Test("generateActiveContracts returns a non-empty list")
    func generatesContracts() {
        #expect(!SGXParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)).isEmpty)
    }

    @Test("All generated contracts have a future expiration")
    func allContractsAreFuture() {
        let ref = Self.date(2026, 1, 1)
        let contracts = SGXParsing.generateActiveContracts(asOf: ref)
        #expect(contracts.allSatisfy { ($0.expiration ?? .distantFuture) >= ref })
    }

    @Test("Each supported family is covered")
    func allFamiliesCovered() {
        let families = Set(SGXParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)).map { $0.family })
        for code in SGXParsing.supportedCodes {
            #expect(families.contains(code), "\(code) missing from generated contracts")
        }
    }

    @Test("Monthly product (CN) generates 12 contracts, quarterly (NK) generates 8")
    func contractCountsBySchedule() {
        let ref = Self.date(2026, 1, 1)
        let all = SGXParsing.generateActiveContracts(asOf: ref)
        #expect(all.filter { $0.family == "CN" }.count == 12)
        #expect(all.filter { $0.family == "NK" }.count == 8)
        #expect(all.filter { $0.family == "FEF" }.count == 12)
        // NK is quarterly: every symbol carries an H/M/U/Z month code.
        let quarter: Set<Character> = ["H", "M", "U", "Z"]
        let nk = all.filter { $0.family == "NK" }
        #expect(nk.allSatisfy { quarter.contains($0.symbol.dropFirst(2).first ?? "?") })
    }

    @Test("Contracts are sorted by expiration date")
    func contractsAreSorted() {
        let dates = SGXParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)).compactMap { $0.expiration }
        #expect(dates == dates.sorted())
    }

    @Test("Generated symbol round-trips through productCode")
    func symbolRoundTrips() {
        for c in SGXParsing.generateActiveContracts(asOf: Self.date(2026, 1, 1)) {
            #expect(SGXParsing.productCode(fromSymbol: c.symbol) == c.family)
        }
    }

    // MARK: - Front contract

    @Test("Front contract is the nearest non-expired one")
    func frontContractSelection() {
        let ref = Self.date(2026, 1, 1)
        let cn = SGXParsing.generateActiveContracts(asOf: ref).filter { $0.family == "CN" }
        let front = InstrumentSelection.frontContract(cn, family: "CN", now: ref)
        #expect(front != nil)
        #expect(front?.expiration == cn.compactMap { $0.expiration }.min())
    }
}
