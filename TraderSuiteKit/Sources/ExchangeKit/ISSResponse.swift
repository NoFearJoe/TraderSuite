import Foundation

/// One cell in an ISS `data` row. ISS mixes strings, numbers and nulls.
/// Numbers are decoded as `Decimal` to preserve precision for money math.
enum ISSValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Decimal)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let d = try? c.decode(Decimal.self) {
            self = .number(d)
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Numeric value, also parsing numbers that ISS returned as strings.
    var decimalValue: Decimal? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Decimal(string: s)
        default: return nil
        }
    }
}

/// A single ISS response block (e.g. "securities", "marketdata").
/// `metadata` is ignored — request with `iss.meta=off`.
struct ISSBlock: Decodable, Sendable {
    let columns: [String]
    let data: [[ISSValue]]

    /// Re-keys each row by its column name for convenient lookup.
    func rows() -> [[String: ISSValue]] {
        data.map { row in
            var dict: [String: ISSValue] = [:]
            for (index, name) in columns.enumerated() where index < row.count {
                dict[name] = row[index]
            }
            return dict
        }
    }
}

/// Top-level ISS response: a dictionary of named blocks.
typealias ISSDocument = [String: ISSBlock]
