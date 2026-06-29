import SwiftUI
import Core
import Persistence

/// Lot-sizing screen for a single instrument: pick a deposit, enter the trade,
/// choose a risk level, and read out the recommended lot count, the loss at the
/// stop and the margin (ГО) required. The result is a flush card at the bottom
/// that can be expanded or collapsed.
struct LotCalcView: View {
    @Environment(AppEnvironment.self) private var env
    let detail: InstrumentDetail

    @State private var model = LotCalcViewModel()
    @State private var spec: ContractSpec?
    @State private var isLoadingSpec = false
    @State private var specError: String?
    @State private var showingDepositPicker = false
    @State private var selectedDepositID: UUID?
    // Expanded during demo capture so the card shows loss-at-stop + margin.
    @State private var resultExpanded = UITestMode.isActive
    @State private var draftLoaded = false
    @FocusState private var entryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(String(localized: "section_deposit")) {
                    DepositSelectionRow(deposit: selectedDeposit) { showingDepositPicker = true }
                }

                Section(String(localized: "section_trade")) {
                    Picker(String(localized: "field_trade_type"), selection: $model.direction) {
                        Text("trade_direction_buy").tag(TradeDirection.long)
                        Text("trade_direction_sell").tag(TradeDirection.short)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("field_entry_price")
                        Spacer()
                        TextField(String(localized: "field_entry_price"), text: $model.entryText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .focused($entryFocused)
                            .accessibilityIdentifier("calc.entry")
                    }
                    DecimalField(String(localized: "field_stop_loss_price"), text: $model.stopText,
                                 accessibilityID: "calc.stop")
                }

                Section(String(localized: "field_risk")) {
                    RiskSelector(
                        presets: LotCalcViewModel.presetRiskPercents,
                        choice: $model.riskChoice,
                        customText: $model.customRiskText
                    )
                }
            }

            resultCard
        }
        .navigationTitle(Text("action_position_sizing"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                InstrumentHeaderRow(detail: detail)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: clearAll) {
                    Image(systemName: "eraser")
                }
                .disabled(model.draft.isEmpty)
                .accessibilityLabel(Text("action_clear_fields"))
            }
        }
        .sheet(isPresented: $showingDepositPicker) {
            DepositPickerSheet(selectedID: selectedDepositID) { id in
                selectedDepositID = id
                env.selectedDepositID = id
                applyDepositRisk()
            }
        }
        .task { await loadSpec() }
        .task {
            // Focus the entry field once the push transition settles. Skipped
            // during demo capture so the keyboard timing is driven by the test.
            guard !UITestMode.isActive else { return }
            try? await Task.sleep(for: .milliseconds(400))
            entryFocused = true
        }
        .trackScreen(.lotCalc)
        .onChange(of: model.riskChoice) { _, _ in trackRiskSelected() }
        .onAppear {
            loadDraft()
            prepareDeposit()
        }
        .onDisappear {
            trackResult()
            saveDraft()
            UITestMode.writeMarker("end") // video: recording stops here
        }
    }

    // MARK: Analytics

    private func trackRiskSelected() {
        var params: [AnalyticsProperty: String] = [
            .screen: AnalyticsScreen.lotCalc.rawValue,
            .exchange: detail.exchange.rawValue,
            .isPreset: { if case .preset = model.riskChoice { return "true" } else { return "false" } }(),
        ]
        if let whole = model.riskWholePercent {
            params[.riskPercent] = NSDecimalNumber(decimal: whole).stringValue
        }
        env.analytics.log(.riskSelected, params)
    }

    /// Report the final, valid sizing result once, as the screen is dismissed —
    /// avoids an event per keystroke while still capturing whether the user got one.
    private func trackResult() {
        guard let result else { return }
        var params: [AnalyticsProperty: String] = [
            .exchange: detail.exchange.rawValue,
            .symbol: detail.symbol,
            .lots: String(result.lots),
            .limitedByMargin: result.limitedByMargin ? "true" : "false",
        ]
        if let whole = model.riskWholePercent {
            params[.riskPercent] = NSDecimalNumber(decimal: whole).stringValue
        }
        env.analytics.log(.positionCalculated, params)
    }

    // MARK: Result card

    private var resultCard: some View {
        CalcResultCard(state: cardState, expanded: $resultExpanded) {
            if let result {
                HStack {
                    Text("field_lots_count").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(result.lots)").font(.title.weight(.bold))
                }
            }
        } detail: {
            if let result {
                VStack(spacing: 10) {
                    CalcResultRow(L("field_lots_count"), "\(result.lots)", prominent: true)
                    Divider()
                    CalcResultRow(L("field_loss_at_stop"), formatMoney(result.lossAtStop, currencyCode: currency))
                    CalcResultRow(L("field_margin_short"), formatMoney(result.margin, currencyCode: currency))
                    if result.limitedByMargin {
                        CalcWarning(L("warning_margin_limited"))
                    }
                }
            }
        }
    }

    private var outcome: LotCalcViewModel.Outcome {
        model.outcome(depositBalance: selectedDeposit?.balance, spec: spec)
    }

    private var cardState: CalcCardState {
        if isLoadingSpec { return .loading }
        if let specError { return .error(specError) }
        switch outcome {
        case .empty: return .empty(L("empty_calc_prompt"))
        case .invalid(let message): return .error(message)
        case .value: return .ready
        }
    }

    private var result: LotCalcResult? {
        if case .value(let value) = outcome { return value }
        return nil
    }

    // MARK: Deposits

    private var deposits: [DepositEntity] {
        (try? env.deposits.deposits(forExchange: detail.exchange.rawValue)) ?? []
    }

    private var selectedDeposit: DepositEntity? {
        deposits.first { $0.id == selectedDepositID } ?? deposits.first
    }

    private var currency: String {
        selectedDeposit?.currencyCode ?? detail.exchange.currencyCode
    }

    private func prepareDeposit() {
        if selectedDepositID == nil {
            selectedDepositID = env.selectedDepositID ?? deposits.first?.id
        }
        env.selectedDepositID = selectedDepositID
        // A restored draft already carries the user's last risk choice; only seed
        // from the deposit when there was nothing to restore.
        if !draftLoaded { applyDepositRisk() }
    }

    private func applyDepositRisk() {
        if let deposit = selectedDeposit { model.applyDepositRisk(deposit.riskPercent) }
    }

    // MARK: Draft persistence

    private func loadDraft() {
        guard let entity = try? env.calcDrafts.draft(
                exchangeIDRaw: detail.exchange.rawValue,
                symbol: detail.symbol,
                kindRaw: CalcKind.lot.rawValue),
              let draft = try? JSONDecoder().decode(LotCalcDraft.self, from: entity.payload)
        else { return }
        model.apply(draft)
        draftLoaded = true
    }

    private func saveDraft() {
        let draft = model.draft
        if draft.isEmpty {
            try? env.calcDrafts.delete(
                exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol, kindRaw: CalcKind.lot.rawValue)
        } else if let data = try? JSONEncoder().encode(draft) {
            try? env.calcDrafts.save(
                exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol,
                kindRaw: CalcKind.lot.rawValue, payload: data)
        }
    }

    private func clearAll() {
        model.clear()
        applyDepositRisk()
        draftLoaded = false
        try? env.calcDrafts.delete(
            exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol, kindRaw: CalcKind.lot.rawValue)
        entryFocused = true
    }

    // MARK: Loading

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
