import Foundation

/// Commission per contract. Exchange fee usually comes from the spec,
/// the broker fee is a user setting. Both are per side.
public struct CommissionModel: Sendable, Hashable {
    public let exchangeFeePerSide: Decimal
    public let brokerFeePerSide: Decimal

    public init(exchangeFeePerSide: Decimal, brokerFeePerSide: Decimal) {
        self.exchangeFeePerSide = exchangeFeePerSide
        self.brokerFeePerSide = brokerFeePerSide
    }

    /// Convenience: take the exchange fee from the spec, add the user's broker fee.
    public init(spec: ContractSpec, brokerFeePerSide: Decimal) {
        self.exchangeFeePerSide = spec.exchangeFeePerSide
        self.brokerFeePerSide = brokerFeePerSide
    }

    /// Total commission to open AND close one lot (entry + exit).
    public var roundTripPerLot: Decimal {
        (exchangeFeePerSide + brokerFeePerSide) * 2
    }
}
