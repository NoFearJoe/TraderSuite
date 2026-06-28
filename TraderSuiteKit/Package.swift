// swift-tools-version: 6.2
import PackageDescription

// Local package holding all of the app's modules.
// The thin Xcode App target (see ../App) depends on `Features`, which pulls the rest.
//
// Dependency graph:
//   Core         (no deps)        — domain models + calculation engine
//   ExchangeKit  -> Core          — exchange adapter protocol + registry (MOEX in Phase 2)
//   Persistence  -> Core          — SwiftData models + container (CloudKit sync in Phase 3)
//   Features     -> Core,         — SwiftUI screens + view models
//                   ExchangeKit,
//                   Persistence
//
// swift-tools-version 6.0 puts every target in Swift 6 language mode
// (full data-race safety) by default.
let package = Package(
    name: "TraderSuiteKit",
    defaultLocalization: "ru",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "ExchangeKit", targets: ["ExchangeKit"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Features", targets: ["Features"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "ExchangeKit", dependencies: ["Core"]),
        .target(name: "Persistence", dependencies: ["Core"]),
        .target(
            name: "Features",
            dependencies: ["Core", "ExchangeKit", "Persistence"]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ExchangeKitTests", dependencies: ["ExchangeKit"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
    ]
)
