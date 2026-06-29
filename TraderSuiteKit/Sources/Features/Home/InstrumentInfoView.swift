import SwiftUI
import Core
import ExchangeKit
import Persistence

/// A value snapshot of an instrument used for navigation, so screens never read
/// a possibly-deleted SwiftData entity (a watchlist can be removed while viewed).
struct InstrumentDetail: Hashable {
    let exchange: ExchangeID
    let family: String
    let symbol: String
    let expiration: Date?
    let iconURLString: String?

    init(exchange: ExchangeID, family: String, symbol: String, expiration: Date?, iconURLString: String?) {
        self.exchange = exchange
        self.family = family
        self.symbol = symbol
        self.expiration = expiration
        self.iconURLString = iconURLString
    }

    /// Snapshot a watchlist. `nil` if its stored exchange id is unknown.
    init?(watchlist: WatchlistEntity) {
        guard let exchange = ExchangeID(rawValue: watchlist.exchangeIDRaw) else { return nil }
        self.init(
            exchange: exchange,
            family: watchlist.family,
            symbol: watchlist.activeSymbol,
            expiration: watchlist.activeExpiration,
            iconURLString: watchlist.iconURLString
        )
    }

    /// Rebuild an `InstrumentSummary` (e.g. to re-add as a watchlist).
    var asSummary: InstrumentSummary {
        InstrumentSummary(
            symbol: symbol,
            family: family,
            displayName: symbol,
            isPerpetual: expiration == nil,
            expiration: expiration,
            iconURL: iconURLString.flatMap(URL.init(string:))
        )
    }
}

/// Detailed information about a futures contract: name, icon, description,
/// expiration, the exchange's numeric spec, a watchlist toggle, and entry points
/// to the lot-sizing and averaging calculators.
struct InstrumentInfoView: View {
    @Environment(AppEnvironment.self) private var env
    let detail: InstrumentDetail
    let model: WatchlistViewModel

    @State private var spec: ContractSpec?
    @State private var isLoadingSpec = false
    @State private var specError: String?
    @State private var showingNotificationSetup = false
    @State private var showPaywall = false

    private var artwork: InstrumentArtwork { InstrumentArtwork.forFamily(detail.family) }
    private var name: String { artwork.title ?? detail.family }
    private var summary: String { artwork.summary ?? String(format: String(localized: "instrument_summary_fallback"), detail.symbol) }
    private var currency: String { detail.exchange.currencyCode }
    private var isWatchlist: Bool { model.isWatchlist(symbol: detail.symbol, exchange: detail.exchange) }
    private var isFavLimitReached: Bool {
        !env.subscriptions.isSubscribed && model.count(for: detail.exchange) >= SubscriptionLimit.watchlist
    }

    var body: some View {
        Form {
            header
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            Section(String(localized: "section_about_contract")) {
                ResultRow(String(localized: "field_identifier"), detail.symbol)
                ResultRow(String(localized: "field_exchange"), detail.exchange.displayName)
                if let _ = detail.expiration {
                    ResultRow(String(localized: "field_expiration"), formatDate(detail.expiration!))
                    if isWatchlist {
                        notificationRow
                    }
                }
            }
            specSection
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                InstrumentHeaderRow(detail: detail)
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleWatchlist) {
                    Image(systemName: isWatchlist ? "star.fill" : "star")
                }
                .proGated(!isWatchlist && isFavLimitReached, feature: .watchlist)
                .accessibilityLabel(isWatchlist
                    ? String(localized: "action_remove_from_watchlist")
                    : String(localized: "action_add_to_watchlist"))
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(isPresented: $showingNotificationSetup) {
            ExpirationNotificationSetupView(detail: detail, model: model)
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionView()
                .onAppear { env.analytics.log(.paywallShown, [.source: AnalyticsSource.notificationRow.rawValue]) }
        }
        .trackScreen(.instrumentInfo)
        .task { await loadSpec() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 10) {
            InstrumentIcon(iconURLString: detail.iconURLString, family: detail.family, size: 72)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var specSection: some View {
        Section {
            if isLoadingSpec {
                HStack {
                    Text("loading_exchange_data").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            } else if let spec {
                ResultRow(String(localized: "field_price_step"), formatDecimal(spec.minStep))
                ResultRow(String(localized: "field_step_value"), formatMoney(spec.stepPrice, currencyCode: currency))
                ResultRow(String(localized: "field_initial_margin"), formatMoney(spec.initialMargin, currencyCode: currency))
                ResultRow(String(localized: "field_exchange_fee"), formatMoney(spec.exchangeFeePerSide, currencyCode: currency))
            } else if let specError {
                Text(specError).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("section_exchange_data")
        }
    }

    /// Pinned bottom bar: the two calculators side by side, always on screen.
    /// Fixed-height buttons with the icon centred above the (wrapping) title.
    private var actionBar: some View {
        HStack(spacing: 12) {
            navButton(String(localized: "action_averaging"), systemImage: "arrow.triangle.merge", route: .averaging(detail), tint: .gray)
            navButton(String(localized: "action_position_sizing"), systemImage: "function", route: .calc(detail), tint: .accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func navButton(_ title: String, systemImage: String, route: HomeRoute, tint: Color) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.headline)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
    }

    // MARK: Notification row

    private var currentWatchlist: WatchlistEntity? {
        model.watchlist.first {
            $0.family == detail.family && $0.exchangeIDRaw == detail.exchange.rawValue
        }
    }

    private var notificationRow: some View {
        Button {
            if env.subscriptions.isSubscribed {
                showingNotificationSetup = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack {
                Label(
                    String(localized: "field_notification"),
                    systemImage: currentWatchlist?.notificationEnabled == true ? "bell.badge.fill" : "bell"
                )
                Spacer()
                Text(notificationStatusText)
                    .font(.subheadline)
                    .foregroundStyle(currentWatchlist?.notificationEnabled == true ? .black : .gray)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var notificationStatusText: String {
        guard let fav = currentWatchlist, fav.notificationEnabled else {
            return String(localized: "notification_status_off")
        }
        return leadDaysText(fav.notificationLeadDays)
    }

    private func leadDaysText(_ days: Int) -> String {
        switch days {
        case 0: return String(localized: "notification_lead_0")
        case 1: return String(localized: "notification_lead_1")
        case 2...4: return String(format: String(localized: "notification_lead_n_few"), Int64(days))
        case 7: return String(localized: "notification_lead_7")
        default: return String(format: String(localized: "notification_lead_n_many"), Int64(days))
        }
    }

    // MARK: Actions

    private func toggleWatchlist() {
        if isWatchlist {
            env.analytics.log(.instrumentRemoved, [
                .exchange: detail.exchange.rawValue, .symbol: detail.symbol,
            ])
            model.removeWatchlist(symbol: detail.symbol, exchange: detail.exchange)
        } else {
            env.analytics.log(.instrumentAdded, [
                .exchange: detail.exchange.rawValue,
                .family: detail.family,
                .symbol: detail.symbol,
                .source: AnalyticsSource.instrumentInfo.rawValue,
            ])
            Task { await model.addWatchlist(contract: detail.asSummary, exchange: detail.exchange) }
        }
    }

    private func loadSpec() async {
        isLoadingSpec = true
        specError = nil
        defer { isLoadingSpec = false }
        do {
            spec = try await env.specProvider.spec(symbol: detail.symbol, exchange: detail.exchange)
        } catch {
            specError = L("error_load_contract_spec")
        }
    }
}
