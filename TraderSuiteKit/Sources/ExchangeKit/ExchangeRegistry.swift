import Foundation

/// Thread-safe registry mapping an `ExchangeID` to its adapter.
/// An actor because adapters are registered once at launch and read concurrently.
public actor ExchangeRegistry {
    private var adapters: [ExchangeID: any ExchangeAdapter] = [:]

    public init() {}

    /// Seed the registry with adapters synchronously (actor init runs before any
    /// concurrent access), so callers don't have to `await register` at launch.
    public init(adapters: [any ExchangeAdapter]) {
        for adapter in adapters {
            self.adapters[adapter.exchangeID] = adapter
        }
    }

    public func register(_ adapter: any ExchangeAdapter) {
        adapters[adapter.exchangeID] = adapter
    }

    public func adapter(for id: ExchangeID) -> (any ExchangeAdapter)? {
        adapters[id]
    }

    public var registeredExchanges: [ExchangeID] {
        Array(adapters.keys)
    }
}
