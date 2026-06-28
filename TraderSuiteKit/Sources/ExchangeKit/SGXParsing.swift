import Foundation
import Core

/// Which calendar months have active contracts for an SGX product.
enum SGXContractSchedule: Sendable {
    case quarterly      // H, M, U, Z  — Nikkei 225
    case monthly        // all 12      — China A50, Iron Ore
}

/// Formula for the last trading day of an SGX product. Like the other adapters,
/// all rules approximate exchange holidays as weekends only.
enum SGXExpirationRule: Sendable {
    /// Second-last business day of the contract month (FTSE China A50).
    case secondLastBusinessDay
    /// Last business day of the contract month (Iron Ore 62% Fe).
    case lastBusinessDay
    /// The day before the second Friday of the contract month (Nikkei 225, whose
    /// Special Quotation is fixed on the second Friday).
    case dayBeforeSecondFriday
}

/// Pure functions for SGX data: a static product catalogue and local contract
/// generation, mirroring `EurexParsing`. SGX has no free per-contract margin API,
/// so `defaultMargin` and the numeric specs are approximate static figures.
///
/// IMPORTANT: the multipliers / margins below are best-effort approximations and
/// MUST be reconciled against the official SGX contract specifications before
/// release — `stepPrice` in particular feeds position sizing directly.
///
/// All products are USD settled. Symbols follow the same internal convention as
/// the other exchanges: product code + month code + 2-digit year, e.g. "NKH26".
enum SGXParsing {

    // MARK: - Product database

    struct ProductSpec: Sendable {
        let productCode: String
        let displayName: String
        let minStep: Decimal
        let stepPrice: Decimal
        let exchangeFeePerSide: Decimal
        /// Approximate initial margin in USD (static; see type doc).
        let defaultMargin: Decimal
        let schedule: SGXContractSchedule
        let expirationRule: SGXExpirationRule
    }

    static let supportedCodes: [String] = ["CN", "NK", "FEF"]

    static let products: [String: ProductSpec] = {
        func p(
            _ code: String, _ name: String,
            _ step: Decimal, _ tickVal: Decimal, _ fee: Decimal, _ margin: Decimal,
            _ schedule: SGXContractSchedule, _ rule: SGXExpirationRule
        ) -> (String, ProductSpec) {
            (code, ProductSpec(
                productCode: code, displayName: name,
                minStep: step, stepPrice: tickVal,
                exchangeFeePerSide: fee, defaultMargin: margin,
                schedule: schedule, expirationRule: rule
            ))
        }
        return Dictionary(uniqueKeysWithValues: [
            // FTSE China A50: US$1 × index, tick 2.5 pts → US$2.50/tick.
            p("CN",  "FTSE China A50",     2.5,   2.5,  0.50,  1500, .monthly,   .secondLastBusinessDay),
            // USD Nikkei 225: US$5 × index, tick 5 pts → US$25/tick.
            p("NK",  "USD Nikkei 225",     5.0,  25.0,  0.50, 11000, .quarterly, .dayBeforeSecondFriday),
            // Iron Ore 62% Fe: 100 dmt, US$0.01/dmt tick → US$1.00/tick.
            p("FEF", "Iron Ore 62% Fe",    0.01,  1.0,  0.50,  1500, .monthly,   .lastBusinessDay),
        ])
    }()

    /// How many contracts to generate per product, by schedule.
    static func contractCount(for schedule: SGXContractSchedule) -> Int {
        switch schedule {
        case .quarterly: return 8    // ~2 years
        case .monthly:   return 12   // ~1 year
        }
    }

    // MARK: - Month code tables

    static let monthCodeToInt: [String: Int] = [
        "F": 1, "G": 2, "H": 3, "J": 4, "K": 5, "M": 6,
        "N": 7, "Q": 8, "U": 9, "V": 10, "X": 11, "Z": 12,
    ]

    private static let intToMonthCode: [Int: String] = [
        1: "F", 2: "G", 3: "H", 4: "J", 5: "K", 6: "M",
        7: "N", 8: "Q", 9: "U", 10: "V", 11: "X", 12: "Z",
    ]

    private static let monthCodeSet: Set<String> = [
        "F", "G", "H", "J", "K", "M", "N", "Q", "U", "V", "X", "Z",
    ]

    private static let monthsBySchedule: [SGXContractSchedule: Set<String>] = [
        .quarterly: ["H", "M", "U", "Z"],
        .monthly:   ["F", "G", "H", "J", "K", "M", "N", "Q", "U", "V", "X", "Z"],
    ]

    // MARK: - Static contract generation

    /// Builds the full list of active SGX contracts without any network call.
    static func generateActiveContracts(asOf now: Date) -> [InstrumentSummary] {
        var result: [InstrumentSummary] = []
        for code in supportedCodes {
            guard let spec = products[code] else { continue }
            result.append(contentsOf: upcomingContracts(code: code, spec: spec, asOf: now))
        }
        return result.sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }

    // MARK: - Spec lookup

    /// Extracts the SGX product code from a full symbol, e.g. "NKH26" → "NK".
    /// Scans from the right: strips the 1–2 digit year, then one month-code letter.
    static func productCode(fromSymbol symbol: String) -> String? {
        let chars = Array(symbol.uppercased())
        guard chars.count >= 3 else { return nil }
        var idx = chars.endIndex - 1
        while idx > chars.startIndex, chars[idx].isNumber { idx -= 1 }
        guard monthCodeSet.contains(String(chars[idx])), idx > chars.startIndex else { return nil }
        let code = String(chars[..<idx])
        return code.isEmpty ? nil : code
    }

    /// Builds a `ContractSpec` from the static product database.
    static func parseSpec(symbol: String) throws -> ContractSpec {
        guard let code = productCode(fromSymbol: symbol),
              let spec = products[code] else {
            throw ExchangeError.instrumentNotFound(symbol)
        }
        return ContractSpec(
            symbol: symbol,
            minStep: spec.minStep,
            stepPrice: spec.stepPrice,
            initialMargin: spec.defaultMargin,
            exchangeFeePerSide: spec.exchangeFeePerSide
        )
    }

    // MARK: - Expiration date calculation

    static func expirationDate(
        rule: SGXExpirationRule,
        monthCode: String,
        year: Int
    ) -> Date? {
        guard let month = monthCodeToInt[monthCode] else { return nil }
        switch rule {
        case .lastBusinessDay:
            return nthToLastWeekday(1, month: month, year: year)
        case .secondLastBusinessDay:
            return nthToLastWeekday(2, month: month, year: year)
        case .dayBeforeSecondFriday:
            guard let fri = nthWeekday(2, weekday: 6, month: month, year: year) else { return nil }
            return sgxCalendar().date(byAdding: .day, value: -1, to: fri)
        }
    }

    // MARK: - Private: contract generation

    private static func upcomingContracts(
        code: String,
        spec: ProductSpec,
        asOf now: Date
    ) -> [InstrumentSummary] {
        let cal = sgxCalendar()
        let comps = cal.dateComponents([.month, .year], from: now)
        var month = comps.month!
        var year  = comps.year!

        let activeCodes = monthsBySchedule[spec.schedule] ?? []
        let target = contractCount(for: spec.schedule)
        var result: [InstrumentSummary] = []

        for _ in 0..<48 {            // scan at most 48 calendar months
            guard result.count < target else { break }
            if let mc = intToMonthCode[month], activeCodes.contains(mc) {
                if let exp = expirationDate(rule: spec.expirationRule, monthCode: mc, year: year),
                   exp >= now {
                    let y2 = String(format: "%02d", year % 100)
                    let symbol = code + mc + y2
                    let name = "\(spec.displayName) \(friendlyMonth(month, y2))"
                    result.append(InstrumentSummary(
                        symbol: symbol, family: code,
                        displayName: name, isPerpetual: false, expiration: exp
                    ))
                }
            }
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return result
    }

    // MARK: - Private: weekday math

    /// Nth occurrence of `weekday` (1=Sun…7=Sat) in a month; `n` is 1-based.
    private static func nthWeekday(_ n: Int, weekday wd: Int, month: Int, year: Int) -> Date? {
        let cal = sgxCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let first = cal.date(from: c) else { return nil }
        let firstWD = cal.component(.weekday, from: first)
        let daysToFirst = (wd - firstWD + 7) % 7
        return cal.date(byAdding: .day, value: daysToFirst + (n - 1) * 7, to: first)
    }

    /// Nth-to-last weekday of a month (`n`=1 → last business day). Weekends skipped.
    private static func nthToLastWeekday(_ n: Int, month: Int, year: Int) -> Date? {
        let cal = sgxCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else { return nil }
        c.day = range.upperBound - 1
        guard var day = cal.date(from: c) else { return nil }
        var count = 0
        while true {
            let wd = cal.component(.weekday, from: day)
            if wd != 1 && wd != 7 {
                count += 1
                if count == n { return day }
            }
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
    }

    // MARK: - Private: helpers

    private static func sgxCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Singapore") ?? .gmt
        return cal
    }

    private static func friendlyMonth(_ month: Int, _ year2: String) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let name = (1...12).contains(month) ? names[month - 1] : "\(month)"
        return "\(name) '\(year2)"
    }
}
