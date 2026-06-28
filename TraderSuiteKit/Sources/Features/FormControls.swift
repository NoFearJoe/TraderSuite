import SwiftUI

/// A right-aligned labeled numeric text field, used across the calc/averaging
/// forms. Decimal keypad on iOS.
struct DecimalField: View {
    let title: String
    @Binding var text: String
    /// Stable identifier for UI tests (the localized title isn't reliable across
    /// languages). Falls back to the title when unset.
    var accessibilityID: String?

    init(_ title: String, text: Binding<String>, accessibilityID: String? = nil) {
        self.title = title
        self._text = text
        self.accessibilityID = accessibilityID
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: $text)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .accessibilityIdentifier(accessibilityID ?? title)
        }
    }
}

/// A label/value row for result sections.
struct ResultRow: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
