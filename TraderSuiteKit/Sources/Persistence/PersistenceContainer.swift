import Foundation
import SwiftData
import Core

public enum PersistenceContainer {
    /// The full SwiftData schema for the app.
    public static let schema = Schema([
        DepositEntity.self,
        WatchlistEntity.self,
        CachedSpecEntity.self,
        CalcDraftEntity.self,
    ])

    /// How the store syncs to iCloud.
    ///
    /// Sync is **disabled by default** so the app builds and runs locally with
    /// ad-hoc signing (no Development Team, no iCloud entitlement). Turning it on
    /// requires the iCloud → CloudKit capability and a matching container ID in
    /// the App target's entitlements — see README.
    public enum CloudKitMode: Sendable {
        /// Local-only store (default).
        case disabled
        /// Sync to the app's default CloudKit container.
        case automatic
        /// Sync to a specific private CloudKit container, e.g.
        /// `"iCloud.com.ilyakharabet.futurescalc"`.
        case privateDatabase(containerIdentifier: String)

        var configuration: ModelConfiguration.CloudKitDatabase {
            switch self {
            case .disabled: return .none
            case .automatic: return .automatic
            case .privateDatabase(let id): return .private(id)
            }
        }
    }

    /// Builds the model container.
    /// - Parameters:
    ///   - inMemory: use a throwaway store (tests / previews). Forces `cloudKit`
    ///     to `.disabled` — an in-memory store cannot sync.
    ///   - cloudKit: iCloud sync mode. Defaults to `.disabled` (see `CloudKitMode`).
    @MainActor
    public static func make(
        inMemory: Bool = false,
        cloudKit: CloudKitMode = .disabled
    ) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: cloudKit.configuration
            )
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

public extension CachedSpecEntity {
    /// Map a cached entity to the calculation-layer value type.
    func asContractSpec() -> ContractSpec {
        ContractSpec(
            symbol: symbol,
            minStep: minStep,
            stepPrice: stepPrice,
            initialMargin: initialMargin,
            exchangeFeePerSide: exchangeFeePerSide
        )
    }
}
