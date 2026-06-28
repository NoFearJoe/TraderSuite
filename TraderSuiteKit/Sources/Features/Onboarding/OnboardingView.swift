import SwiftUI

/// First-launch tutorial. A short paged flow that explains why the app exists and
/// its two core calculators, ending on a subscription promo screen. Presented over
/// `RootView` once (gated by a persisted flag) and dismissed via `onFinish`.
///
/// Native paged swiping via `TabView`'s page style on iOS; macOS — where that style
/// is unavailable — falls back to button-driven paging with a fade.
public struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env

    /// Called when the user finishes or skips the tutorial. The caller persists
    /// the "seen" flag and dismisses.
    private let onFinish: () -> Void

    @State private var page = 0
    @State private var showPaywall = false

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    /// The informational pages, in order. The promo screen is appended after them.
    private static let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            tint: .blue,
            title: "onboarding_welcome_title",
            description: "onboarding_welcome_desc"
        ),
        OnboardingPage(
            icon: "function",
            tint: .green,
            title: "onboarding_calc_title",
            description: "onboarding_calc_desc"
        ),
        OnboardingPage(
            icon: "arrow.triangle.merge",
            tint: .orange,
            title: "onboarding_averaging_title",
            description: "onboarding_averaging_desc"
        ),
    ]

    /// The promo screen is only part of the flow for non-subscribers — there's
    /// nothing to sell to someone who already has the subscription.
    private var showsPromo: Bool { !env.subscriptions.isSubscribed }
    private var totalPages: Int { Self.pages.count + (showsPromo ? 1 : 0) }
    private var isPromo: Bool { showsPromo && page == Self.pages.count }
    private var isLastPage: Bool { page == totalPages - 1 }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            footer
        }
        .sheet(isPresented: $showPaywall) { SubscriptionView() }
        // A successful purchase in the paywall: dismiss the paywall and end the
        // tutorial. Guarding on `showPaywall` keeps a background entitlement change
        // (e.g. a restore on another device) from yanking the user out mid-tutorial.
        .onChange(of: env.subscriptions.isSubscribed) { _, subscribed in
            guard subscribed, showPaywall else { return }
            showPaywall = false
            onFinish()
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Spacer()
//            if !isLastPage {
                Button(action: onFinish) {
                    Text("onboarding_skip")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
//            }
        }
        .frame(height: 28)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        // Native paged swiping. We keep our own dots in the footer, so the built-in
        // page indicator is hidden. `page` is shared with the footer button.
        TabView(selection: $page) {
            ForEach(0..<Self.pages.count, id: \.self) { index in
                OnboardingPageView(page: Self.pages[index]).tag(index)
            }
            if showsPromo {
                PromoPage().tag(Self.pages.count)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        Group {
            if isPromo {
                PromoPage()
            } else if Self.pages.indices.contains(page) {
                OnboardingPageView(page: Self.pages[page])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .id(page) // re-trigger the fade on every page change
        #endif
    }

    private var footer: some View {
        VStack(spacing: 18) {
            PageDots(count: totalPages, current: page)

            Button(action: advance) {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    // MARK: - Actions

    /// Promo screen → open the paywall; final info page (subscribers, no promo) →
    /// finish; otherwise advance to the next page.
    private var primaryButtonTitle: LocalizedStringKey {
        if isPromo { return "onboarding_promo_subscribe" }
        return isLastPage ? "onboarding_start" : "onboarding_next"
    }

    private func advance() {
        if isPromo {
            showPaywall = true
        } else if isLastPage {
            onFinish()
        } else {
            withAnimation(.snappy) { page += 1 }
        }
    }
}

// MARK: - Info page

/// One informational onboarding page: a tinted icon, a title and a short description.
struct OnboardingPage {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: page.icon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(page.tint)
                .frame(width: 132, height: 132)
                .background(page.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 32, style: .continuous))

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Promo page

/// The closing subscription promo. Opens with the "experienced trader?" hook, then
/// lists what the subscription unlocks. The actual purchase happens in the native
/// `SubscriptionView` paywall, opened from the footer's primary button.
private struct PromoPage: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
                    .shadow(color: .yellow.opacity(0.4), radius: 12)
                Text("onboarding_promo_question")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("onboarding_promo_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

/// One feature row on the promo screen: a tinted icon chip, a bold title and a
/// short description of what the subscription unlocks.
private struct OnboardingFeatureRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Page indicator

/// Row of dots marking the current page. The active dot is the accent colour.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environment(AppEnvironment.inMemory())
}
