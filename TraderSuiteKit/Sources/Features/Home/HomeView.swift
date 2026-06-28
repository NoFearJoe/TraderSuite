import SwiftUI
import ExchangeKit
import Persistence

/// The app's single root screen:
/// - a settings button (top-left) and an exchange selector (top-right);
/// - the watchlist list for the selected exchange (or a placeholder when empty);
/// - a native bottom search field to find and add instruments.
///
/// Destinations it pushes (settings, instrument info, lot/averaging calculators)
/// are resolved in `destination(_:model:)` below.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: WatchlistViewModel?
    @State private var query = ""
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var env = env
        NavigationStack(path: $path) {
            Group {
                if let model {
                    HomeContent(
                        model: model,
                        query: query,
                        exchange: env.selectedExchange,
                        path: $path,
                        onClearSearch: { query = "" }
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("watchlist_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                ToolbarItem(placement: settingsPlacement) {
                    NavigationLink(value: HomeRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(Text("settings_title"))
                    .accessibilityIdentifier("home.settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    ExchangeMenu(selected: $env.selectedExchange)
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                destination(route, model: model)
            }
            .searchable(
                text: $query,
                placement: .toolbar,
                prompt: Text("search_futures_prompt")
            )
            .onChange(of: query) { _, newValue in
                Task { await model?.search(newValue, exchange: env.selectedExchange) }
            }
            .onChange(of: env.selectedExchange) { _, _ in
                Task { await model?.search(query, exchange: env.selectedExchange) }
            }
        }
        .task { await start() }
        .task { await env.subscriptions.start() }
        .onAppear { UITestMode.writeMarker("start") } // video: recording begins here
    }

    // MARK: Lifecycle

    private func start() async {
        if model == nil {
            model = WatchlistViewModel(
                store: env.watchlist,
                registry: env.registry,
                scheduler: env.notificationScheduler
            )
        }
        guard let model else { return }
        // Notification permission is requested lazily when the user opens the
        // expiration-reminder setup screen, not at launch.
        _ = await model.rolloverExpired()
        await model.syncReminders()
    }

    // MARK: Destinations

    @ViewBuilder
    private func destination(_ route: HomeRoute, model: WatchlistViewModel?) -> some View {
        switch route {
        case .settings:
            SettingsView()
        case .info(let detail):
            if let model {
                InstrumentInfoView(detail: detail, model: model)
            } else {
                ProgressView()
            }
        case .calc(let detail):
            LotCalcView(detail: detail)
        case .averaging(let detail):
            AveragingCalcView(detail: detail)
        }
    }

    private var settingsPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}

/// Navigation targets reachable from the home screen.
enum HomeRoute: Hashable {
    case settings
    case info(InstrumentDetail)
    case calc(InstrumentDetail)
    case averaging(InstrumentDetail)
}

// MARK: - Content

/// Switches between the watchlist list and search results based on the live
/// search state. Lives in its own view so it can read `\.isSearching`, which is
/// only published to descendants of the `.searchable` container.
private struct HomeContent: View {
    @Environment(\.isSearching) private var isSearchActive
    let model: WatchlistViewModel
    let query: String
    let exchange: ExchangeID
    @Binding var path: NavigationPath
    let onClearSearch: () -> Void

    var body: some View {
        if isSearchActive {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView(
                    String(localized: "search_empty_prompt"),
                    systemImage: "magnifyingglass"
                )
            } else {
                SearchResultsList(model: model, exchange: exchange, onAdded: onClearSearch)
            }
        } else {
            watchlistList
        }
    }

    private var exchangeWatchlist: [WatchlistEntity] {
        model.watchlist.filter { $0.exchangeIDRaw == exchange.rawValue }
    }

    @ViewBuilder
    private var watchlistList: some View {
        let items = exchangeWatchlist
        if items.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "empty_watchlist_title"), systemImage: "star")
            } description: {
                Text("empty_watchlist_description")
            }
        } else {
            List {
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                ForEach(items) { watchlist in
                    WatchlistRow(
                        watchlist: watchlist,
                        onOpen: { navigate(to: watchlist) { .info($0) } },
                        onCalc: { navigate(to: watchlist) { .calc($0) } },
                        onAveraging: { navigate(to: watchlist) { .averaging($0) } }
                    )
                }
                .onMove { source, destination in
                    model.move(items, from: source, to: destination)
                }
                .onDelete { offsets in
                    for index in offsets where items.indices.contains(index) {
                        model.remove(items[index])
                    }
                }
            }
        }
    }

    /// Snapshot a watchlist into an `InstrumentDetail` and push the chosen route.
    private func navigate(to watchlist: WatchlistEntity, route: (InstrumentDetail) -> HomeRoute) {
        if let detail = InstrumentDetail(watchlist: watchlist) {
            path.append(route(detail))
        }
    }
}

// MARK: - Exchange selector

/// Top-right control: the current exchange's flag + name, tappable to switch.
private struct ExchangeMenu: View {
    @Binding var selected: ExchangeID

    var body: some View {
        Menu {
            Picker(String(localized: "field_exchange"), selection: $selected) {
                ForEach(ExchangeID.allCases, id: \.self) { exchange in
                    Label {
                        Text(exchange.displayName)
                    } icon: {
                        Text(exchange.flag)
                    }
                    .tag(exchange)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selected.flag)
                Text(selected.displayName).fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Выбор биржи, текущая \(selected.displayName)")
    }
}

// MARK: - Watchlist row

/// The instrument's icon: the exchange's own artwork when available, otherwise a
/// locally-generated icon based on the instrument family (see `InstrumentArtwork`).
struct InstrumentIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let iconURLString: String?
    let family: String
    var size: CGFloat = 40

    /// The glyph reads white in light mode and black in dark mode, so it stays
    /// legible against the tinted glass surface in either theme.
    private var glyphColor: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        if let iconURLString, let url = URL(string: iconURLString) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                generated
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            generated
        }
    }

    private var generated: some View {
        let artwork = InstrumentArtwork.forFamily(family)
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        if artwork.isFallback {
            let letter = String(family.prefix(1)).uppercased()
            return AnyView(
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(glyphColor)
                    .frame(width: size, height: size)
                    .instrumentIconSurface(tint: .secondary, in: shape)
            )
        } else {
            return AnyView(
                Image(systemName: artwork.systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(glyphColor)
                    .frame(width: size, height: size)
                    .instrumentIconSurface(tint: artwork.tint, in: shape)
            )
        }
    }
}

private extension View {
    /// Surface behind a locally-generated instrument icon: Liquid Glass, tinted to
    /// the instrument's colour, on iOS/macOS 26+; a flat translucent fill before.
    @ViewBuilder
    func instrumentIconSurface(tint: Color, in shape: some Shape) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(tint, in: shape)
        }
    }
}

/// A watchlist cell: a futures icon, the instrument name + identifier, and two
/// round action buttons (lot calc, averaging). Tapping the row opens the
/// instrument detail. Navigation is programmatic (plain `Button`s, not
/// `NavigationLink`s) so the row shows no disclosure indicator and a row tap
/// pushes exactly one screen.
private struct WatchlistRow: View {
    let watchlist: WatchlistEntity
    let onOpen: () -> Void
    let onCalc: () -> Void
    let onAveraging: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    InstrumentIcon(iconURLString: watchlist.iconURLString, family: watchlist.family)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(watchlist.displayName).font(.headline)
                        Text(watchlist.activeSymbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watchlistRow.open")

            Button(action: onAveraging) {
                VStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.merge")
                        .font(.system(size: 14, weight: .semibold))
                    Text("averaging_title")
                        .font(.system(size: 9, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .accessibilityIdentifier("watchlistRow.averaging")

            Button(action: onCalc) {
                VStack(spacing: 3) {
                    Image(systemName: "function")
                        .font(.system(size: 14, weight: .semibold))
                    Text("action_position_sizing")
                        .font(.system(size: 9, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .accessibilityIdentifier("watchlistRow.calc")
        }
    }
}

// MARK: - Search results

/// Search hits for one instrument family: a group header plus its contracts,
/// ordered by expiration (the order they already arrive in from the view model).
private struct InstrumentGroup: Identifiable {
    let family: String
    let contracts: [InstrumentSummary]
    var id: String { family }

    /// Group instruments by family, preserving the incoming order both for the
    /// groups (by nearest expiration) and the contracts within each group.
    static func group(_ instruments: [InstrumentSummary]) -> [InstrumentGroup] {
        var order: [String] = []
        var byFamily: [String: [InstrumentSummary]] = [:]
        for instrument in instruments {
            if byFamily[instrument.family] == nil { order.append(instrument.family) }
            byFamily[instrument.family, default: []].append(instrument)
        }
        return order.map { InstrumentGroup(family: $0, contracts: byFamily[$0] ?? []) }
    }
}

/// Search results grouped by instrument. Each group is one section: a header
/// naming the instrument (does nothing when tapped) and a row per contract,
/// sorted by expiration. Tapping a contract adds it to watchlist.
private struct SearchResultsList: View {
    /// How many contracts a group shows before the user expands it.
    private static let collapsedLimit = 2

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var expandedFamilies: Set<String> = []
    let model: WatchlistViewModel
    let exchange: ExchangeID
    /// Called after a successful add so the search field can be cleared.
    let onAdded: () -> Void

    /// Search hits grouped by instrument, excluding only the specific contract
    /// that is already the active symbol in watchlist (other contracts in the
    /// same family remain visible so the user can roll over to them).
    private var groups: [InstrumentGroup] {
        let visible = model.searchResults.filter { contract in
            !model.watchlist.contains {
                $0.exchangeIDRaw == exchange.rawValue &&
                $0.family == contract.family &&
                $0.activeSymbol == contract.symbol
            }
        }
        return InstrumentGroup.group(visible)
    }

    var body: some View {
        Group {
            if model.isSearching {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                ContentUnavailableView.search
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(visibleContracts(group), id: \.symbol) { contract in
                                Button { add(contract) } label: { contractRow(contract) }
                                    .buttonStyle(.plain)
                                    .proGated(isFavLimitReached)
                                    .accessibilityIdentifier("searchResult.\(contract.symbol)")
                            }
                        } header: {
                            header(group)
                        }
                    }
                }
            }
        }
    }

    /// Contracts to show for a group: capped at `collapsedLimit` unless expanded.
    private func visibleContracts(_ group: InstrumentGroup) -> [InstrumentSummary] {
        if expandedFamilies.contains(group.family) { return group.contracts }
        return Array(group.contracts.prefix(Self.collapsedLimit))
    }

    private func header(_ group: InstrumentGroup) -> some View {
        let isExpanded = expandedFamilies.contains(group.family)
        let hidden = group.contracts.count - Self.collapsedLimit
        return HStack(spacing: 12) {
            InstrumentIcon(iconURLString: group.contracts.first?.iconURL?.absoluteString, family: group.family)
            Text(InstrumentArtwork.displayName(forFamily: group.family))
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if hidden > 0 {
                Button {
                    toggle(group.family)
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded
                            ? String(localized: "action_collapse")
                            : String(format: String(localized: "action_show_more"), hidden))
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isExpanded
                    ? String(localized: "accessibility_collapse_contracts")
                    : String(format: String(localized: "accessibility_show_more_contracts"), hidden))
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    private func toggle(_ family: String) {
        withAnimation(.snappy) {
            if expandedFamilies.contains(family) {
                expandedFamilies.remove(family)
            } else {
                expandedFamilies.insert(family)
        }
        }
    }

    private func contractRow(_ contract: InstrumentSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contract.displayName).font(.body)
                if let expiration = contract.expiration {
                    Text("\(formatDate(expiration))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
    }

    private var isFavLimitReached: Bool {
        !env.subscriptions.isSubscribed && model.count(for: exchange) >= SubscriptionLimit.watchlist
    }

    private func add(_ contract: InstrumentSummary) {
        Task {
            if await model.addWatchlist(contract: contract, exchange: exchange) {
                onAdded()
                dismissSearch()
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppEnvironment.inMemory())
}
