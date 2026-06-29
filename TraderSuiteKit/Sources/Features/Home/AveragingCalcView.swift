import SwiftUI
import Core
import Persistence

/// Position-averaging screen for a single instrument: list the open positions
/// (entry + lots), add the new position's entry, set a common stop and a
/// per-position risk, and read out how many lots to add — total and per position.
struct AveragingCalcView: View {
    @Environment(AppEnvironment.self) private var env
    let detail: InstrumentDetail

    @State private var model = AveragingCalcViewModel()
    @State private var spec: ContractSpec?
    @State private var isLoadingSpec = false
    @State private var specError: String?
    @State private var showingDepositPicker = false
    @State private var selectedDepositID: UUID?
    // Expanded during demo capture so the card shows the full breakdown.
    @State private var resultExpanded = UITestMode.isActive
    @State private var draftLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(String(localized: "section_deposit")) {
                    DepositSelectionRow(deposit: selectedDeposit) { showingDepositPicker = true }
                }

                Section(String(localized: "field_trade_type")) {
                    Picker(String(localized: "field_trade_type"), selection: $model.direction) {
                        Text("trade_direction_buy").tag(TradeDirection.long)
                        Text("trade_direction_sell").tag(TradeDirection.short)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach($model.legs) { $leg in
                        legRow(entry: $leg.entryText, lots: $leg.lotsText)
                    }
                    .onDelete { model.removeLeg(at: $0) }

                    Button {
                        model.addLeg()
                    } label: {
                        Label(String(localized: "action_add_position"), systemImage: "plus")
                    }
                    .disabled(!model.canAddLeg)
                } header: {
                    Text("section_open_positions")
                } footer: {
                    Text("open_positions_description")
                }

                Section(String(localized: "new_position_label")) {
                    DecimalField(String(localized: "field_entry_price"), text: $model.newEntryText)
                }

                Section(String(localized: "field_stop_loss")) {
                    DecimalField(String(localized: "field_common_stop"), text: $model.stopText)
                }

                Section(String(localized: "field_risk_per_position")) {
                    RiskSelector(
                        presets: AveragingCalcViewModel.presetRiskPercents,
                        choice: $model.riskChoice,
                        customText: $model.customRiskText
                    )
                }
            }

            resultCard
        }
        .navigationTitle(Text("averaging_title"))
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
        .trackScreen(.averaging)
        .onChange(of: model.riskChoice) { _, _ in trackRiskSelected() }
        .onAppear {
            loadDraft()
            prepareDeposit()
        }
        .onDisappear {
            trackResult()
            saveDraft()
        }
    }

    // MARK: Analytics

    private func trackRiskSelected() {
        var params: [AnalyticsProperty: String] = [
            .screen: AnalyticsScreen.averaging.rawValue,
            .exchange: detail.exchange.rawValue,
            .isPreset: { if case .preset = model.riskChoice { return "true" } else { return "false" } }(),
        ]
        if let whole = model.riskWholePercent {
            params[.riskPercent] = NSDecimalNumber(decimal: whole).stringValue
        }
        env.analytics.log(.riskSelected, params)
    }

    /// Report the final averaging result once, as the screen is dismissed.
    private func trackResult() {
        guard let result else { return }
        env.analytics.log(.averagingCalculated, [
            .exchange: detail.exchange.rawValue,
            .symbol: detail.symbol,
            .lots: String(result.totalLots),
        ])
    }

    // MARK: Position rows

    private func legRow(entry: Binding<String>, lots: Binding<String>) -> some View {
        HStack(spacing: 12) {
            DecimalField(String(localized: "field_entry_price"), text: entry)
            Divider().frame(height: 22)
            TextField(String(localized: "field_lots"), text: lots)
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }

    // MARK: Result card

    private var resultCard: some View {
        CalcResultCard(state: cardState, expanded: $resultExpanded) {
            if let result {
                HStack {
                    Text("field_total_lots").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(result.totalLots)").font(.title.weight(.bold))
                }
            }
        } detail: {
            if let result {
                VStack(spacing: 10) {
                    CalcResultRow(L("field_add_lots"), "\(result.newLots)", prominent: true)
                    Divider()
                    ForEach(Array(result.perPositionLots.enumerated()), id: \.offset) { index, lots in
                        CalcResultRow(positionLabel(index, count: result.perPositionLots.count), "\(lots) \(L("inline_lot"))")
                    }
                    Divider()
                    CalcResultRow(L("field_total_lots"), "\(result.totalLots)")
                    CalcResultRow(L("field_average_price"), formatDecimal(result.averagePrice))
                    CalcResultRow(L("field_loss_at_stop"), formatMoney(result.lossAtStop, currencyCode: currency))
                    CalcResultRow(L("field_margin_short"), formatMoney(result.margin, currencyCode: currency))
                    if !result.canAdd {
                        CalcWarning(L("warning_risk_budget_exhausted"))
                    } else if result.limitedByMargin {
                        CalcWarning(L("warning_margin_limited"))
                    }
                }
            }
        }
    }

    private func positionLabel(_ index: Int, count: Int) -> String {
        index == count - 1
            ? String(localized: "new_position_label")
            : String(format: String(localized: "position_label_numbered"), index + 1)
    }

    private var outcome: AveragingCalcViewModel.Outcome {
        model.outcome(depositBalance: selectedDeposit?.balance, spec: spec)
    }

    private var cardState: CalcCardState {
        if isLoadingSpec { return .loading }
        if let specError { return .error(specError) }
        switch outcome {
        case .empty: return .empty(L("empty_averaging_prompt"))
        case .invalid(let message): return .error(message)
        case .value: return .ready
        }
    }

    private var result: AveragingDisplay? {
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
                kindRaw: CalcKind.averaging.rawValue),
              let draft = try? JSONDecoder().decode(AveragingCalcDraft.self, from: entity.payload)
        else { return }
        model.apply(draft)
        draftLoaded = true
    }

    private func saveDraft() {
        let draft = model.draft
        if draft.isEmpty {
            try? env.calcDrafts.delete(
                exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol, kindRaw: CalcKind.averaging.rawValue)
        } else if let data = try? JSONEncoder().encode(draft) {
            try? env.calcDrafts.save(
                exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol,
                kindRaw: CalcKind.averaging.rawValue, payload: data)
        }
    }

    private func clearAll() {
        model.clear()
        applyDepositRisk()
        draftLoaded = false
        try? env.calcDrafts.delete(
            exchangeIDRaw: detail.exchange.rawValue, symbol: detail.symbol, kindRaw: CalcKind.averaging.rawValue)
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
