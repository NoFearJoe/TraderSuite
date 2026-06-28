import SwiftUI
import SwiftData
import Features
import ExchangeKit
import Persistence

// This file belongs to the Xcode App target (not the package).
// Replace Xcode's generated `…App.swift` with this one and add the local
// package `FuturesCalcKit` as a dependency (see README).
@main
struct TraderSuiteApp: App {
    let container: ModelContainer
    @State private var environment: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            // CloudKit sync is off by default so local ad-hoc builds work.
            // To enable: add the iCloud→CloudKit capability, then pass
            // `cloudKit: .automatic` here. See README.
            container = try PersistenceContainer.make()
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error)")
        }
        self.container = container
        let registry = AppEnvironment.makeDefaultRegistry()
        _environment = State(initialValue: AppEnvironment(container: container, registry: registry))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .modelContainer(container)
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
