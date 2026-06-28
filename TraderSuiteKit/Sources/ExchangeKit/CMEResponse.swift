import Foundation

/// Response from CME's initial-margin endpoint.
struct CMEMarginsDocument: Decodable, Sendable {
    let margins: [CMEMarginRow]?
    /// Some endpoints return a flat `initial` at the top level.
    let initial: String?
}

struct CMEMarginRow: Decodable, Sendable {
    let productCode: String?
    let initial: String?
    let maintenance: String?
}
