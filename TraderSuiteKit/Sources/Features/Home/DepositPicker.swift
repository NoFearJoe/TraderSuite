import SwiftUI
import ExchangeKit
import Persistence

/// Deposit selection screen: lists deposits to switch the active one and offers a
/// navbar button to add a new deposit. Presented as a popup over the calculators.
struct DepositPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    @State private var model: DepositsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(Text("deposits_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action_done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        DepositCreateView(initialExchange: env.selectedExchange) { name, exchange, balance in
                            create(name: name, exchange: exchange, balance: balance)
                        }
                    } label: {
                        Label(String(localized: "action_add_deposit"), systemImage: "plus")
                    }
                    .proGated(isDepositLimitReached)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { if model == nil { model = DepositsViewModel(store: env.deposits, exchangeFilter: env.selectedExchange) } }
    }

    private var isDepositLimitReached: Bool {
        !env.subscriptions.isSubscribed &&
        (model?.deposits.count ?? 0) >= SubscriptionLimit.depositsPerExchange
    }

    @ViewBuilder
    private func content(_ model: DepositsViewModel) -> some View {
        if model.deposits.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "empty_deposits_title"), systemImage: "banknote")
            } description: {
                Text("empty_deposits_description")
            }
        } else {
            List(model.deposits) { deposit in
                Button {
                    onSelect(deposit.id)
                    dismiss()
                } label: {
                    row(deposit)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ deposit: DepositEntity) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(deposit.name).foregroundStyle(.primary)
                Text("\(formatMoney(deposit.balance, currencyCode: deposit.currencyCode))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if deposit.id == selectedID {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    /// Persist a new deposit (default 2% risk) and select it. Returns success.
    private func create(name: String, exchange: ExchangeID, balance: String) -> Bool {
        guard let model,
              let created = model.addDeposit(
                name: name,
                exchange: exchange,
                balanceText: balance,
                riskPercentText: "2"
              )
        else { return false }
        onSelect(created.id)
        return true
    }
}

/// Create a deposit: name, balance and the exchange it belongs to. The currency
/// is derived from the exchange (not chosen separately). Risk defaults to 2%.
struct DepositCreateView: View {
    /// Persist the deposit; returns true on success so the screen can dismiss.
    let onCreate: (_ name: String, _ exchange: ExchangeID, _ balance: String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var exchange: ExchangeID
    @State private var balance = ""
    @State private var error: String?

    init(initialExchange: ExchangeID = .moex, onCreate: @escaping (String, ExchangeID, String) -> Bool) {
        self.onCreate = onCreate
        _exchange = State(initialValue: initialExchange)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "field_name"), text: $name)

                Picker(String(localized: "field_exchange"), selection: $exchange) {
                    ForEach(ExchangeID.allCases, id: \.self) { exchange in
                        Label {
                            Text(exchange.displayName)
                        } icon: {
                            Text(exchange.flag)
                        }
                        .tag(exchange)
                    }
                }

                HStack {
                    Text("Размер")
                    Spacer()
                    TextField("0", text: $balance)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(exchange.currencyCode).foregroundStyle(.secondary)
                }
            } footer: {
                Text(String(format: String(localized: "deposit_currency_note"), exchange.currencyCode))
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(Text("new_deposit_title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "action_save"), action: save)
            }
        }
    }

    private func save() {
        guard let amount = parseDecimal(balance), amount > 0 else {
            error = L("error_deposit_balance_invalid")
            return
        }
        if onCreate(name, exchange, balance) {
            dismiss()
        } else {
            error = L("error_save_deposit_inline")
        }
    }
}

/// Edit an existing deposit: name, balance and per-trade risk. The exchange (and
/// thus the currency) is fixed once created and shown read-only.
struct DepositEditView: View {
    let deposit: DepositEntity
    /// Persist the edits; returns true on success so the screen can dismiss.
    let onSave: (_ name: String, _ balance: String, _ risk: String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var balance: String
    @State private var risk: String
    @State private var error: String?

    init(deposit: DepositEntity, onSave: @escaping (String, String, String) -> Bool) {
        self.deposit = deposit
        self.onSave = onSave
        _name = State(initialValue: deposit.name)
        _balance = State(initialValue: NSDecimalNumber(decimal: deposit.balance).stringValue)
        _risk = State(initialValue: formatPercent(deposit.riskPercent))
    }

    private var exchange: ExchangeID? { ExchangeID(rawValue: deposit.exchangeIDRaw) }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "field_name"), text: $name)

                HStack {
                    Text("Размер")
                    Spacer()
                    TextField("0", text: $balance)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(deposit.currencyCode).foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(localized: "field_risk_per_trade"))
                    Spacer()
                    TextField("2", text: $risk)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            } footer: {
                if let exchange {
                    Text("Биржа: \(exchange.flag) \(exchange.displayName)")
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(Text("section_deposit"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "action_save"), action: save)
            }
        }
    }

    private func save() {
        if onSave(name, balance, risk) {
            dismiss()
        } else {
            error = L("error_deposit_invalid")
        }
    }
}
