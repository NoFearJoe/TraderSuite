import SwiftUI
import ExchangeKit
import Persistence

/// Deposits management reached from Settings: list all deposits, add new ones and
/// delete. Selection for calculations lives elsewhere; this screen just curates
/// the list.
struct DepositsListView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: DepositsViewModel?

    var body: some View {
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
        .task { if model == nil { model = DepositsViewModel(store: env.deposits) } }
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
            List {
                ForEach(model.deposits) { deposit in
                    NavigationLink {
                        DepositEditView(deposit: deposit) { name, balance, risk in
                            model.updateDeposit(deposit, name: name, balanceText: balance, riskPercentText: risk)
                        }
                    } label: {
                        row(deposit)
                    }
                }
                .onDelete { offsets in
                    model.delete(at: offsets)
                    reconcileSelection(model)
                }
            }
        }
    }

    private func row(_ deposit: DepositEntity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deposit.name)
            Text("\(formatMoney(deposit.balance, currencyCode: deposit.currencyCode))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var isDepositLimitReached: Bool {
        guard !env.subscriptions.isSubscribed else { return false }
        let count = (try? env.deposits.deposits(forExchange: env.selectedExchange.rawValue))?.count ?? 0
        return count >= SubscriptionLimit.depositsPerExchange
    }

    private func create(name: String, exchange: ExchangeID, balance: String) -> Bool {
        guard let model,
              model.addDeposit(name: name, exchange: exchange, balanceText: balance, riskPercentText: "2") != nil
        else { return false }
        return true
    }

    /// Keep the active selection valid if the selected deposit was deleted.
    private func reconcileSelection(_ model: DepositsViewModel) {
        if let id = env.selectedDepositID, !model.deposits.contains(where: { $0.id == id }) {
            env.selectedDepositID = model.deposits.first?.id
        }
    }
}
