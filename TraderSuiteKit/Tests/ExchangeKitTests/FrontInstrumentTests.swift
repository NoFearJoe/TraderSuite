import Testing
import Foundation
import Core
@testable import ExchangeKit

private func mskDay(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
    return cal.date(from: DateComponents(year: y, month: m, day: d))!
}

/// Adapter that serves a fixed instrument list; relies on the protocol's default
/// `frontInstrument` implementation.
private struct ListAdapter: ExchangeAdapter {
    let exchangeID: ExchangeID = .moex
    let instruments: [InstrumentSummary]

    func fetchInstruments() async throws -> [InstrumentSummary] { instruments }
    func fetchSpec(symbol: String) async throws -> ContractSpec {
        ContractSpec(symbol: symbol, minStep: 1, stepPrice: 1, initialMargin: 1)
    }
    func resolveFrontContract(family: String) async throws -> ContractSpec {
        try await fetchSpec(symbol: frontInstrument(family: family).symbol)
    }
}

@Suite("Front instrument resolution")
struct FrontInstrumentTests {
    private let instruments = [
        InstrumentSummary(symbol: "SiM6", family: "Si", displayName: "Si-6.26", isPerpetual: false, expiration: mskDay(2026, 6, 18)),
        InstrumentSummary(symbol: "SiU6", family: "Si", displayName: "Si-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18)),
        InstrumentSummary(symbol: "RIU6", family: "RTS", displayName: "RTS-9.26", isPerpetual: false, expiration: mskDay(2026, 9, 18)),
    ]

    @Test("Picks the nearest non-expired contract for a family")
    func picksFront() async throws {
        let adapter = ListAdapter(instruments: instruments)
        let front = try await adapter.frontInstrument(family: "Si", now: mskDay(2026, 6, 14))
        #expect(front.symbol == "SiM6")
    }

    @Test("Skips an expired front and rolls to the next")
    func rollsAfterExpiry() async throws {
        let adapter = ListAdapter(instruments: instruments)
        let front = try await adapter.frontInstrument(family: "Si", now: mskDay(2026, 6, 19))
        #expect(front.symbol == "SiU6")
    }

    @Test("Unknown family throws instrumentNotFound")
    func unknownFamily() async {
        let adapter = ListAdapter(instruments: instruments)
        await #expect(throws: ExchangeError.instrumentNotFound("ZZ")) {
            _ = try await adapter.frontInstrument(family: "ZZ", now: mskDay(2026, 6, 14))
        }
    }
}
