import SwiftUI

/// App root. A single screen (no tab bar): watchlist, exchange selection,
/// settings and instrument search all live in `HomeView`. Requires an
/// `AppEnvironment` in the SwiftUI environment.
///
/// On first launch it presents the `OnboardingView` tutorial over the home
/// screen, gated by a persisted flag so it only appears once.
public struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    /// Persisted across launches: becomes `true` once the tutorial is finished
    /// or skipped, so onboarding shows exactly once.
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var showOnboarding = false

    public init() {}

    public var body: some View {
        HomeView()
            .onAppear { showOnboarding = !onboardingCompleted }
            .onboardingCover(isPresented: $showOnboarding) {
                onboardingCompleted = true
                showOnboarding = false
                env.analytics.log(.onboardingCompleted)
            }
    }
}

private extension View {
    /// Presents the onboarding tutorial: full-screen on iOS, a sized sheet on macOS
    /// (where `fullScreenCover` is unavailable).
    @ViewBuilder
    func onboardingCover(isPresented: Binding<Bool>, onFinish: @escaping () -> Void) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented) {
            OnboardingView(onFinish: onFinish)
        }
        #else
        sheet(isPresented: isPresented) {
            OnboardingView(onFinish: onFinish)
                .frame(minWidth: 480, minHeight: 620)
        }
        #endif
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.inMemory())
}
