import Foundation
import Core

/// Which calendar months have active contracts for this product.
enum CMEContractSchedule: Sendable {
    case quarterly      // H, M, U, Z  — equity index, FX, treasuries
    case monthly        // all 12      — CL, NG
    case biMonthly      // G, J, M, Q, V, Z — gold
    case silverMonths   // H, K, N, U, Z
}

/// Formula used to calculate the last trading day for this product.
/// All rules approximate exchange holidays as weekends only.
enum CMEExpirationRule: Sendable {
    /// Third Friday of the delivery month (ES, NQ, RTY, YM, MES, MNQ).
    case thirdFriday
    /// 7 weekdays before the last weekday of the delivery month (ZB, ZN).
    case seventhBeforeLastWeekday
    /// 2 weekdays before the third Wednesday of the delivery month (6E, 6J, 6B).
    case twoBeforeThirdWednesday
    /// 3 weekdays before the 25th of the month prior to delivery (CL).
    case thirdBeforeTwentyFifthPrior
    /// 3 weekdays before the 1st of the delivery month (NG).
    case threeBeforeFirstOfMonth
    /// Third-to-last weekday of the delivery month (GC, SI).
    case thirdToLastWeekday
}

/// Pure functions for CME data: static contract generation and spec lookup.
/// Month codes follow the CFTC convention: F G H J K M N Q U V X Z (Jan–Dec).
enum CMEParsing {

    // MARK: - Product database

    struct ProductSpec: Sendable {
        let productCode: String
        let displayName: String
        let minStep: Decimal
        let stepPrice: Decimal
        let exchangeFeePerSide: Decimal
        /// Approximate initial margin in USD; used when the live fetch fails.
        let defaultMargin: Decimal
        let schedule: CMEContractSchedule
        let expirationRule: CMEExpirationRule
    }

    static let supportedCodes: [String] = [
        "ES", "NQ", "RTY", "YM", "MES", "MNQ",
        "CL", "NG",
        "GC", "SI",
        "ZB", "ZN",
        "6E", "6J", "6B",
    ]

    // swiftlint:disable identifier_name
    static let products: [String: ProductSpec] = {
        func p(
            _ code: String, _ name: String,
            _ step: Decimal, _ tickVal: Decimal, _ fee: Decimal, _ margin: Decimal,
            _ schedule: CMEContractSchedule, _ rule: CMEExpirationRule
        ) -> (String, ProductSpec) {
            (code, ProductSpec(
                productCode: code, displayName: name,
                minStep: step, stepPrice: tickVal,
                exchangeFeePerSide: fee, defaultMargin: margin,
                schedule: schedule, expirationRule: rule
            ))
        }
        return Dictionary(uniqueKeysWithValues: [
            p("ES",  "E-mini S&P 500",       0.25,       12.5,   1.45, 15600, .quarterly,    .thirdFriday),
            p("NQ",  "E-mini Nasdaq-100",     0.25,        5.0,   1.45, 21000, .quarterly,    .thirdFriday),
            p("RTY", "E-mini Russell 2000",   0.10,        5.0,   1.45,  6600, .quarterly,    .thirdFriday),
            p("YM",  "E-mini Dow Jones",      1.0,         5.0,   1.45,  7920, .quarterly,    .thirdFriday),
            p("MES", "Micro E-mini S&P 500",  0.25,        1.25,  0.22,  1560, .quarterly,    .thirdFriday),
            p("MNQ", "Micro E-mini Nasdaq",   0.25,        0.50,  0.22,  2100, .quarterly,    .thirdFriday),
            p("CL",  "Crude Oil",             0.01,       10.0,   1.45,  6000, .monthly,      .thirdBeforeTwentyFifthPrior),
            p("NG",  "Natural Gas",           0.001,      10.0,   1.45,  2500, .monthly,      .threeBeforeFirstOfMonth),
            p("GC",  "Gold",                  0.10,       10.0,   1.50,  9900, .biMonthly,    .thirdToLastWeekday),
            p("SI",  "Silver",                0.005,      25.0,   1.50,  9000, .silverMonths, .thirdToLastWeekday),
            p("ZB",  "T-Bond 30Y",            0.03125,    31.25,  0.65,  2200, .quarterly,    .seventhBeforeLastWeekday),
            p("ZN",  "T-Note 10Y",            0.015625,   15.625, 0.65,  1050, .quarterly,    .seventhBeforeLastWeekday),
            p("6E",  "Euro FX",               0.00005,     6.25,  1.45,  3000, .quarterly,    .twoBeforeThirdWednesday),
            p("6J",  "Japanese Yen",          0.0000005,   6.25,  1.45,  2750, .quarterly,    .twoBeforeThirdWednesday),
            p("6B",  "British Pound",         0.0001,      6.25,  1.45,  2500, .quarterly,    .twoBeforeThirdWednesday),
        ])
    }()
    // swiftlint:enable identifier_name

    // MARK: - Month code tables

    static let monthCodeToInt: [String: Int] = [
        "F":1,"G":2,"H":3,"J":4,"K":5,"M":6,
        "N":7,"Q":8,"U":9,"V":10,"X":11,"Z":12,
    ]

    private static let intToMonthCode: [Int: String] = [
        1:"F",2:"G",3:"H",4:"J",5:"K",6:"M",
        7:"N",8:"Q",9:"U",10:"V",11:"X",12:"Z",
    ]

    private static let monthCodeSet: Set<String> = [
        "F","G","H","J","K","M","N","Q","U","V","X","Z",
    ]

    private static let monthsBySchedule: [CMEContractSchedule: Set<String>] = [
        .quarterly:    ["H","M","U","Z"],
        .monthly:      ["F","G","H","J","K","M","N","Q","U","V","X","Z"],
        .biMonthly:    ["G","J","M","Q","V","Z"],
        .silverMonths: ["H","K","N","U","Z"],
    ]

    // MARK: - Static contract generation

    /// Builds the full list of active CME contracts without any network call.
    /// Covers the next 18–24 months of contracts for each supported product.
    static func generateActiveContracts(asOf now: Date) -> [InstrumentSummary] {
        var result: [InstrumentSummary] = []
        for code in supportedCodes {
            guard let spec = products[code] else { continue }
            result.append(contentsOf: upcomingContracts(code: code, spec: spec, asOf: now))
        }
        return result.sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }

    // MARK: - Spec lookup

    /// Extracts the CME product code from a full symbol, e.g. "ESH26" → "ES".
    /// Scans from the right: strips 1–2 digit year, then the month-code letter.
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
    /// - Parameters:
    ///   - symbol: Full CME symbol, e.g. "ESH26".
    ///   - margin: Live initial margin override; `nil` falls back to `defaultMargin`.
    static func parseSpec(symbol: String, margin: Decimal? = nil) throws -> ContractSpec {
        guard let code = productCode(fromSymbol: symbol),
              let spec = products[code] else {
            throw ExchangeError.instrumentNotFound(symbol)
        }
        return ContractSpec(
            symbol: symbol,
            minStep: spec.minStep,
            stepPrice: spec.stepPrice,
            initialMargin: margin ?? spec.defaultMargin,
            exchangeFeePerSide: spec.exchangeFeePerSide
        )
    }

    /// Extracts the initial margin from a live CMEMarginsDocument response.
    static func parseMargin(_ doc: CMEMarginsDocument, productCode: String) -> Decimal? {
        if let flat = doc.initial, let d = cleanDecimal(flat) { return d }
        return doc.margins?
            .first { $0.productCode?.uppercased() == productCode.uppercased() }
            .flatMap { cleanDecimal($0.initial ?? "") }
    }

    // MARK: - Date helpers (kept for external/test use)

    /// Parses an expiration date string in ISO ("YYYY-MM-DD") or US ("MM/DD/YY") format.
    static func parseExpDate(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if let d = parseISO(s) { return d }
        return parseUSDate(s)
    }

    // MARK: - Private: contract generation

    private static func upcomingContracts(
        code: String,
        spec: ProductSpec,
        asOf now: Date
    ) -> [InstrumentSummary] {
        let cal = cmeCalendar()
        let comps = cal.dateComponents([.month, .year], from: now)
        var month = comps.month!
        var year  = comps.year!

        let activeCodes = monthsBySchedule[spec.schedule] ?? []
        let target = contractCount(for: spec.schedule)
        var result: [InstrumentSummary] = []

        for _ in 0..<36 {            // scan at most 36 calendar months
            guard result.count < target else { break }
            if let code2 = intToMonthCode[month], activeCodes.contains(code2) {
                if let exp = expirationDate(rule: spec.expirationRule, monthCode: code2, year: year),
                   exp >= now {
                    let y2 = String(format: "%02d", year % 100)
                    let symbol = code + code2 + y2
                    let name = "\(spec.displayName) \(friendlyMonth(code2, y2))"
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

    private static func contractCount(for schedule: CMEContractSchedule) -> Int {
        switch schedule {
        case .quarterly:    return 8    // 2 years
        case .monthly:      return 18   // 1.5 years
        case .biMonthly:    return 8    // ~16 months
        case .silverMonths: return 6    // ~18 months
        }
    }

    // MARK: - Private: expiration date calculation

    static func expirationDate(
        rule: CMEExpirationRule,
        monthCode: String,
        year: Int
    ) -> Date? {
        guard let month = monthCodeToInt[monthCode] else { return nil }
        switch rule {
        case .thirdFriday:
            return thirdWeekday(weekday: 6, month: month, year: year)  // 6=Friday
        case .seventhBeforeLastWeekday:
            guard let last = lastWeekday(month: month, year: year) else { return nil }
            return subtractWeekdays(from: last, count: 7)
        case .twoBeforeThirdWednesday:
            guard let wed = thirdWeekday(weekday: 4, month: month, year: year) else { return nil }
            return subtractWeekdays(from: wed, count: 2)
        case .thirdBeforeTwentyFifthPrior:
            var pm = month - 1, py = year
            if pm < 1 { pm = 12; py -= 1 }
            guard let d25 = makeDate(year: py, month: pm, day: 25) else { return nil }
            return subtractWeekdays(from: d25, count: 3)
        case .threeBeforeFirstOfMonth:
            guard let first = makeDate(year: year, month: month, day: 1) else { return nil }
            return subtractWeekdays(from: first, count: 3)
        case .thirdToLastWeekday:
            return thirdToLastWeekday(month: month, year: year)
        }
    }

    /// Nth occurrence of `weekday` (1=Sun…7=Sat) in a month; `n` is 1-based.
    private static func nthWeekday(_ n: Int, weekday wd: Int, month: Int, year: Int) -> Date? {
        let cal = cmeCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let first = cal.date(from: c) else { return nil }
        let firstWD = cal.component(.weekday, from: first)
        let daysToFirst = (wd - firstWD + 7) % 7
        return cal.date(byAdding: .day, value: daysToFirst + (n - 1) * 7, to: first)
    }

    private static func thirdWeekday(weekday: Int, month: Int, year: Int) -> Date? {
        nthWeekday(3, weekday: weekday, month: month, year: year)
    }

    private static func lastWeekday(month: Int, year: Int) -> Date? {
        let cal = cmeCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let firstOfMonth = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
        c.day = range.upperBound - 1
        guard let last = cal.date(from: c) else { return nil }
        let wd = cal.component(.weekday, from: last)
        if wd == 7 { return cal.date(byAdding: .day, value: -1, to: last) }   // Sat → Fri
        if wd == 1 { return cal.date(byAdding: .day, value: -2, to: last) }   // Sun → Fri
        return last
    }

    private static func thirdToLastWeekday(month: Int, year: Int) -> Date? {
        let cal = cmeCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        guard let first = cal.date(from: c),
              let range = cal.range(of: .day, in: .month, for: first) else { return nil }
        c.day = range.upperBound - 1
        guard var day = cal.date(from: c) else { return nil }
        var count = 0
        while count < 3 {
            let wd = cal.component(.weekday, from: day)
            if wd != 1 && wd != 7 { count += 1 }
            if count < 3 { day = cal.date(byAdding: .day, value: -1, to: day)! }
        }
        return day
    }

    private static func subtractWeekdays(from date: Date, count: Int) -> Date {
        let cal = cmeCalendar()
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

    private static func cmeCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return cal
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        let cal = cmeCalendar()
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        return cal.date(from: c)
    }

    private static func friendlyMonth(_ code: String, _ year2: String) -> String {
        let names = [
            "F":"Jan","G":"Feb","H":"Mar","J":"Apr","K":"May","M":"Jun",
            "N":"Jul","Q":"Aug","U":"Sep","V":"Oct","X":"Nov","Z":"Dec",
        ]
        return "\(names[code] ?? code) '\(year2)"
    }

    private static func parseISO(_ s: String) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return makeDate(year: y, month: m, day: d)
    }

    private static func parseUSDate(_ s: String) -> Date? {
        let p = s.split(separator: "/")
        guard p.count == 3, let m = Int(p[0]), let d = Int(p[1]) else { return nil }
        let raw = Int(p[2]) ?? 0
        return makeDate(year: raw < 100 ? 2000 + raw : raw, month: m, day: d)
    }

    private static func cleanDecimal(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ""))
    }
}
