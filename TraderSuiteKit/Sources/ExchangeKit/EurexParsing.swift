import Foundation
import Core

/// Formula used to calculate the last trading day for a Eurex product.
/// Like `CMEParsing`, all rules approximate exchange holidays as weekends only.
enum EurexExpirationRule: Sendable {
    /// Third Friday of the delivery month (equity index futures: FESX, FDAX, FDXS).
    case thirdFriday
    /// Two exchange days before the 10th calendar day of the delivery month
    /// (fixed-income futures: FGBL, FGBM, FGBS). If the 10th is a weekend it rolls
    /// forward to the next weekday before subtracting.
    case twoBeforeTenth
}

/// Pure functions for Eurex data: a static product catalogue and local contract
/// generation. Eurex has no free per-contract margin API (margins are portfolio
/// based, "Prisma"), so `defaultMargin` values are approximate, static figures —
/// good enough for sizing, refreshed by app updates rather than live calls.
///
/// All Eurex futures here are quarterly (month codes H, M, U, Z) and EUR settled.
/// Symbols follow the same internal convention as CME: product code + month code
/// + 2-digit year, e.g. "FESXH26".
enum EurexParsing {

    // MARK: - Product database

    struct ProductSpec: Sendable {
        let productCode: String
        let displayName: String
        let minStep: Decimal
        let stepPrice: Decimal
        let exchangeFeePerSide: Decimal
        /// Approximate initial margin in EUR (static; see type doc).
        let defaultMargin: Decimal
        let expirationRule: EurexExpirationRule
    }

    /// Quarterly contracts per product to generate (8 ≈ 2 years out).
    static let contractsPerProduct = 8

    static let supportedCodes: [String] = [
        "FESX", "FDAX", "FDXS",     // equity index
        "FGBL", "FGBM", "FGBS",     // German yield curve
    ]

    static let products: [String: ProductSpec] = {
        func p(
            _ code: String, _ name: String,
            _ step: Decimal, _ tickVal: Decimal, _ fee: Decimal, _ margin: Decimal,
            _ rule: EurexExpirationRule
        ) -> (String, ProductSpec) {
            (code, ProductSpec(
                productCode: code, displayName: name,
                minStep: step, stepPrice: tickVal,
                exchangeFeePerSide: fee, defaultMargin: margin,
                expirationRule: rule
            ))
        }
        return Dictionary(uniqueKeysWithValues: [
            p("FESX", "EURO STOXX 50",  1.0,   10.0, 0.50,  3500, .thirdFriday),
            p("FDAX", "DAX",            1.0,   25.0, 0.50, 18000, .thirdFriday),
            p("FDXS", "Mini-DAX",       1.0,    5.0, 0.30,  3600, .thirdFriday),
            p("FGBL", "Euro-Bund",      0.01,  10.0, 0.40,  2400, .twoBeforeTenth),
            p("FGBM", "Euro-Bobl",      0.01,  10.0, 0.40,  1200, .twoBeforeTenth),
            p("FGBS", "Euro-Schatz",    0.005,  5.0, 0.40,   700, .twoBeforeTenth),
        ])
    }()

    // MARK: - Month code tables

    static let monthCodeToInt: [String: Int] = [
        "H": 3, "M": 6, "U": 9, "Z": 12,
    ]

    private static let intToMonthCode: [Int: String] = [
        3: "H", 6: "M", 9: "U", 12: "Z",
    ]

    /// All CFTC month-code letters, used to split a symbol into product + month.
    private static let monthCodeSet: Set<String> = [
        "F", "G", "H", "J", "K", "M", "N", "Q", "U", "V", "X", "Z",
    ]

    // MARK: - Static contract generation

    /// Builds the full list of active Eurex contracts without any network call:
    /// the next ~2 years of quarterly contracts for each supported product.
    static func generateActiveContracts(asOf now: Date) -> [InstrumentSummary] {
        var result: [InstrumentSummary] = []
        for code in supportedCodes {
            guard let spec = products[code] else { continue }
            result.append(contentsOf: upcomingContracts(code: code, spec: spec, asOf: now))
        }
        return result.sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }

    // MARK: - Spec lookup

    /// Extracts the Eurex product code from a full symbol, e.g. "FESXH26" → "FESX".
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
        rule: EurexExpirationRule,
        monthCode: String,
        year: Int
    ) -> Date? {
        guard let month = monthCodeToInt[monthCode] else { return nil }
        switch rule {
        case .thirdFriday:
            return thirdWeekday(weekday: 6, month: month, year: year)  // 6 = Friday
        case .twoBeforeTenth:
            guard let tenth = nextWeekday(onOrAfter: 10, month: month, year: year) else { return nil }
            return subtractWeekdays(from: tenth, count: 2)
        }
    }

    // MARK: - Private: contract generation

    private static func upcomingContracts(
        code: String,
        spec: ProductSpec,
        asOf now: Date
    ) -> [InstrumentSummary] {
        let cal = eurexCalendar()
        let comps = cal.dateComponents([.month, .year], from: now)
        var month = comps.month!
        var year  = comps.year!

        var result: [InstrumentSummary] = []
        for _ in 0..<36 {            // scan at most 36 calendar months
            guard result.count < contractsPerProduct else { break }
            if let mc = intToMonthCode[month] {       // quarterly months only
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
        let cal = eurexCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let first = cal.date(from: c) else { return nil }
        let firstWD = cal.component(.weekday, from: first)
        let daysToFirst = (wd - firstWD + 7) % 7
        return cal.date(byAdding: .day, value: daysToFirst + (n - 1) * 7, to: first)
    }

    private static func thirdWeekday(weekday: Int, month: Int, year: Int) -> Date? {
        nthWeekday(3, weekday: weekday, month: month, year: year)
    }

    /// First weekday on or after `day` of the month (rolls a weekend forward).
    private static func nextWeekday(onOrAfter day: Int, month: Int, year: Int) -> Date? {
        let cal = eurexCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        guard var date = cal.date(from: c) else { return nil }
        while case let wd = cal.component(.weekday, from: date), wd == 1 || wd == 7 {
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        return date
    }

    private static func subtractWeekdays(from date: Date, count: Int) -> Date {
        let cal = eurexCalendar()
        var remaining = count
        var current = date
        while remaining > 0 {
            current = cal.date(byAdding: .day, value: -1, to: current)!
            let wd = cal.component(.weekday, from: current)
            if wd != 1 && wd != 7 { remaining -= 1 }
        }
        return current
    }

    // MARK: - Private: helpers

    private static func eurexCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return cal
    }

    private static func friendlyMonth(_ month: Int, _ year2: String) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let name = (1...12).contains(month) ? names[month - 1] : "\(month)"
        return "\(name) '\(year2)"
    }
}
