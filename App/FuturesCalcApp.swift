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
        // App Store asset capture (UI-test target) boots into a deterministic,
        // fully-seeded in-memory environment so screenshots/videos are repeatable.
        if UITestMode.isScreenshots || UITestMode.isVideo {
            let env = UITestMode.isVideo
                ? AppEnvironment.makeForVideo()
                : AppEnvironment.makeForScreenshots()
            self.container = env.container
            _environment = State(initialValue: env)
            return
        }

        let container: ModelContainer
        do {
            // iCloud sync is on: the app declares the CloudKit capability and the
            // `iCloud.com.mesterra.tradersuite` container in TraderSuite.entitlements,
            // and signs with a Development Team (see project.yml). `.automatic`
            // resolves that single container from the entitlements.
            container = try PersistenceContainer.make(cloudKit: .automatic)
        } catch {
            fatalError("Не удалось создать ModelContainer: \(error)")
        }
        self.container = container
        let registry = AppEnvironment.makeDefaultRegistry()
        // Analytics: activate AppMetrica once, then inject its reporter so screens
        // and view models can log usage through the `AnalyticsReporting` seam.
        AppMetricaSetup.activate()
        _environment = State(initialValue: AppEnvironment(
            container: container,
            registry: registry,
            analytics: AppMetricaSetup.makeReporter()
        ))
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
