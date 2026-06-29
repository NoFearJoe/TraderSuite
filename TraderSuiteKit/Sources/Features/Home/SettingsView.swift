import SwiftUI
import StoreKit

/// App settings: deposits management, subscription, sharing/rating and support,
/// with the app version in the footer. Pushed from the gear button on the home
/// screen, so it relies on the surrounding navigation stack.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    @State private var showSubscription = false

    /// App Store listing, used by the share and "rate the app" actions.
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6782816260")!
    private let supportEmail = URL(string: "mailto:mesterra.co@gmail.com")!

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    DepositsListView()
                } label: {
                    Label(String(localized: "deposits_title"), systemImage: "banknote.fill")
                }
            }

            Section {
                Button {
                    env.analytics.log(.paywallShown, [.source: AnalyticsSource.settings.rawValue])
                    showSubscription = true
                } label: {
                    HStack {
                        Label {
                            Text(String(localized: "section_subscription"))
                                .foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                        Text(env.subscriptions.isSubscribed ? L("pro_subscription_title_short") : L("no_subscribtion_title"))
                            .foregroundStyle(.primary)
                            .bold()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary)
                }
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView()
            }

            Section {
                ShareLink(item: appStoreURL) {
                    Label {
                        Text(String(localized: "action_share_app"))
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "square.and.arrow.up.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    env.analytics.log(.appShared)
                })
                Button {
                    env.analytics.log(.appRated)
                    requestReview()
                } label: {
                    Label {
                        Text(String(localized: "action_rate_app"))
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Button {
                    env.analytics.log(.supportContacted)
                    openURL(supportEmail)
                } label: {
                    Label {
                        Text(String(localized: "action_contact_support"))
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } footer: {
                Text("\(String(localized: "field_version")) \(appVersion)")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(Text("settings_title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .trackScreen(.settings)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

/// Subscription management via the native StoreKit subscription screen.
struct SubscriptionView: View {
    @Environment(AppEnvironment.self) private var env
    /// The single Premium subscription product.
    private static let premiumProductID = "com.mesterra.tradersuite.pro"

    var body: some View {
        SubscriptionStoreView(productIDs: [Self.premiumProductID]) {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow)
                        .shadow(color: .yellow.opacity(0.4), radius: 12)
                    Text("pro_subscription_title")
                        .font(.title.weight(.bold))
                    Text("premium_description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer().frame(height: 44)

                VStack(spacing: 14) {
                    PaywallFeatureRow(
                        icon: "banknote",
                        tint: .green,
                        title: "pro_feature_deposits_title",
                        description: "pro_feature_deposits_desc"
                    )
                    PaywallFeatureRow(
                        icon: "star.fill",
                        tint: .orange,
                        title: "pro_feature_watchlist_title",
                        description: "pro_feature_watchlist_desc"
                    )
                    PaywallFeatureRow(
                        icon: "bell.badge.fill",
                        tint: .blue,
                        title: "pro_feature_notifications_title",
                        description: "pro_feature_notifications_desc"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        }
        .storeButton(.visible, for: .restorePurchases)
        // StoreKit's own UI chrome (Subscribe / Restore / price / legal text)
        // localizes off the bundle's resolved language. Pin the environment locale
        // to the app's preferred localization so it matches the rest of the UI
        // instead of falling back to English.
        .environment(\.locale, Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        .trackScreen(.paywall)
        .onInAppPurchaseCompletion { _, result in
            // Fires only on a real completed purchase from this paywall (not on
            // restore or launch-time entitlement refresh), so it's a clean signal.
            if case .success(let purchase) = result, case .success = purchase {
                env.analytics.log(.subscriptionActivated)
            }
        }
    }
}

/// One row in the paywall feature list: a tinted icon chip, a bold title and a
/// short description explaining what the subscription unlocks.
private struct PaywallFeatureRow: View {
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
