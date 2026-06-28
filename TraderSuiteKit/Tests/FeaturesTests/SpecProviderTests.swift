import Testing
import Foundation
import SwiftData
import Core
import ExchangeKit
import Persistence
@testable import Features

/// A controllable stand-in for a real exchange adapter. Counts `fetchSpec`
/// calls so tests can assert on cache hits vs. network round-trips.
private final class FakeAdapter: ExchangeAdapter, @unchecked Sendable {
    let exchangeID: ExchangeID
    private let lock = NSLock()
    private var _fetchCount = 0
    private let result: Result<ContractSpec, ExchangeError>

    var fetchCount: Int { lock.withLock { _fetchCount } }

    init(exchangeID: ExchangeID = .moex, result: Result<ContractSpec, ExchangeError>) {
        self.exchangeID = exchangeID
        self.result = result
    }

    func fetchSpec(symbol: String) async throws -> ContractSpec {
        lock.withLock { _fetchCount += 1 }
        switch result {
        case .success(let spec): return spec
        case .failure(let error): throw error
        }
    }

    func fetchInstruments() async throws -> [InstrumentSummary] { [] }
    func resolveFrontContract(family: String) async throws -> ContractSpec {
        try await fetchSpec(symbol: family)
    }
}

private func spec(_ symbol: String, margin: Decimal = 15_000) -> ContractSpec {
    ContractSpec(symbol: symbol, minStep: 1, stepPrice: 1,
                 initialMargin: margin, exchangeFeePerSide: 2)
}

@MainActor
@Suite("SpecProvider")
struct SpecProviderTests {
    let container: ModelContainer
    let cache: SpecCache

    init() throws {
        container = try PersistenceContainer.make(inMemory: true)
        cache = SpecCache(context: container.mainContext)
    }

    private func makeProvider(_ adapter: FakeAdapter?) async -> SpecProvider {
        let registry = ExchangeRegistry()
        if let adapter { await registry.register(adapter) }
        return SpecProvider(cache: cache, registry: registry)
    }

    @Test("Cache miss fetches once; a fresh hit avoids the network")
    func cacheFirst() async throws {
        let adapter = FakeAdapter(result: .success(spec("Si-6.26")))
        let provider = await makeProvider(adapter)
        let t0 = Date(timeIntervalSince1970: 1_000)

        let first = try await provider.spec(symbol: "Si-6.26", exchange: .moex, now: t0)
        #expect(first.initialMargin == 15_000)
        #expect(adapter.fetchCount == 1)

        // Within TTL: served from cache, no second fetch.
        _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex,
                                    now: t0.addingTimeInterval(60))
        #expect(adapter.fetchCount == 1)
    }

    @Test("A stale entry triggers a refetch")
    func staleRefetches() async throws {
        let adapter = FakeAdapter(result: .success(spec("Si-6.26")))
        let provider = await makeProvider(adapter)
        let t0 = Date(timeIntervalSince1970: 1_000)

        _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex, now: t0)
        let later = t0.addingTimeInterval(SpecCache.defaultMaxAge + 1)
        _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex, now: later)
        #expect(adapter.fetchCount == 2)
    }

    @Test("Network failure falls back to the cached value (offline)")
    func offlineFallback() async throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        // Seed the cache with a known-good value.
        try cache.upsert(spec("Si-6.26", margin: 12_000), exchangeIDRaw: "moex", now: t0)

        let adapter = FakeAdapter(result: .failure(.network("offline")))
        let provider = await makeProvider(adapter)

        // Past TTL → tries network, fails, returns the stale cache entry.
        let later = t0.addingTimeInterval(SpecCache.defaultMaxAge + 1)
        let result = try await provider.spec(symbol: "Si-6.26", exchange: .moex, now: later)
        #expect(result.initialMargin == 12_000)
        #expect(adapter.fetchCount == 1)
    }

    @Test("Network failure with an empty cache throws")
    func unavailableThrows() async throws {
        let adapter = FakeAdapter(result: .failure(.network("offline")))
        let provider = await makeProvider(adapter)

        await #expect(throws: SpecProvider.ProviderError.self) {
            _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex)
        }
    }

    @Test("No registered adapter and no cache throws noAdapter")
    func noAdapterThrows() async throws {
        let provider = await makeProvider(nil)
        await #expect(throws: SpecProvider.ProviderError.noAdapter(.moex)) {
            _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex)
        }
    }

    @Test("refreshSpec bypasses a fresh cache and refetches")
    func refreshBypassesCache() async throws {
        let adapter = FakeAdapter(result: .success(spec("Si-6.26")))
        let provider = await makeProvider(adapter)
        let t0 = Date(timeIntervalSince1970: 1_000)

        _ = try await provider.spec(symbol: "Si-6.26", exchange: .moex, now: t0)
        #expect(adapter.fetchCount == 1)

        // Even though the entry is fresh, refresh forces a network call.
        _ = try await provider.refreshSpec(symbol: "Si-6.26", exchange: .moex,
                                           now: t0.addingTimeInterval(1))
        #expect(adapter.fetchCount == 2)
    }
}
