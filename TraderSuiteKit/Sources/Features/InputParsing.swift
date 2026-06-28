import Foundation
import Core

/// Parse a user-typed number into a `Decimal`, tolerating a comma decimal
/// separator (RU keyboards) and surrounding whitespace. Returns nil for blank
/// or malformed input.
func parseDecimal(_ text: String) -> Decimal? {
    // Drop grouping separators (regular, non-breaking and narrow spaces — the
    // money formatter emits these) and normalise a comma decimal mark.
    let stripped = text.unicodeScalars
        .filter { !CharacterSet.whitespaces.contains($0) && $0 != "\u{202F}" }
        .map(String.init)
        .joined()
        .replacingOccurrences(of: ",", with: ".")
    guard !stripped.isEmpty else { return nil }
    return Decimal(string: stripped)
}
