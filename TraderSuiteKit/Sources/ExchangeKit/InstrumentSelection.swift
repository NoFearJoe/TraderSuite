import Foundation
import Core

/// Exchange-agnostic instrument selection used by watchlist/rollover.
public enum InstrumentSelection {

    /// The nearest non-expired contract for a family — the rollover target.
    /// Perpetual instruments are excluded (they never roll).
    public static func frontContract(
        _ instruments: [InstrumentSummary],
        family: String,
        now: Date
    ) -> InstrumentSummary? {
        instruments
            .filter { $0.family == family && !$0.isPerpetual }
            .filter { ($0.expiration ?? .distantFuture) >= now }
            .min { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
    }
}

public extension ExchangeAdapter {
    /// Resolve the current front instrument (symbol + expiration) for a family.
    /// Generic default over `fetchInstruments()`; adapters may override for speed.
    func frontInstrument(family: String, now: Date = Date()) async throws -> InstrumentSummary {
        let instruments = try await fetchInstruments()
        guard let front = InstrumentSelection.frontContract(instruments, family: family, now: now) else {
            throw ExchangeError.instrumentNotFound(family)
        }
        return front
    }
}
