import SwiftUI
import Foundation

/// The risk-per-trade choice: a standard preset (whole percent) or a custom value.
public enum RiskChoice: Hashable, Codable {
    case preset(Decimal)   // whole percent
    case custom
}

/// Horizontal chips of standard risk presets plus a "custom" option that reveals
/// a free-entry field. Shared by the lot-sizing and averaging screens.
struct RiskSelector: View {
    let presets: [Decimal]
    @Binding var choice: RiskChoice
    @Binding var customText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { percent in
                        chip(label(percent), selected: choice == .preset(percent)) {
                            choice = .preset(percent)
                        }
                    }
                    chip(L("risk_custom"), selected: choice == .custom) {
                        choice = .custom
                    }
                }
                .padding(.vertical, 2)
            }
            if choice == .custom {
                DecimalField(L("field_risk_percent"), text: $customText)
            }
        }
    }

    private func label(_ percent: Decimal) -> String {
        "\(NSDecimalNumber(decimal: percent).stringValue) %"
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.secondary), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
