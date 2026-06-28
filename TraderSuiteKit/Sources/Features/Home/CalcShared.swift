import SwiftUI
import Persistence

/// Compact instrument header (icon + name + identifier) shown at the top of the
/// calculator screens.
struct InstrumentHeaderRow: View {
    let detail: InstrumentDetail

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .center, spacing: 2) {
                Text(InstrumentArtwork.displayName(forFamily: detail.family)).font(.headline)
                Text(detail.symbol).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// The selected-deposit cell that opens the deposit picker on tap. Shared by the
/// calculator screens.
struct DepositSelectionRow: View {
    let deposit: DepositEntity?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let deposit {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deposit.name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(formatMoney(deposit.balance, currencyCode: deposit.currencyCode))")
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("select_deposit_prompt").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
