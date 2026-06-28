import SwiftUI

/// State of a calculator result card independent of the concrete result type.
enum CalcCardState: Equatable {
    case loading
    case empty(String)
    case error(String)
    case ready
}

/// Reusable floating result card for the calculators: a draggable/expandable
/// panel pinned at the bottom of the screen. It renders the loading/empty/error
/// chrome itself; the owner supplies the collapsed summary and expanded detail
/// shown in the `.ready` state.
struct CalcResultCard<Collapsed: View, Detail: View>: View {
    let state: CalcCardState
    @Binding var expanded: Bool
    private let collapsed: Collapsed
    private let detail: Detail

    init(
        state: CalcCardState,
        expanded: Binding<Bool>,
        @ViewBuilder collapsed: () -> Collapsed,
        @ViewBuilder detail: () -> Detail
    ) {
        self.state = state
        self._expanded = expanded
        self.collapsed = collapsed()
        self.detail = detail()
    }

    var body: some View {
        VStack(spacing: 12) {
            handle
            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: expanded)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("loading_data").foregroundStyle(.secondary)
            }
        case .empty(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .error(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineLimit(3)
                .multilineTextAlignment(.center)
        case .ready:
            if expanded { detail } else { collapsed }
        }
    }

    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 40, height: 5)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onEnded { value in
                withAnimation(.snappy) {
                    if value.translation.height < -30 { expanded = true }
                    else if value.translation.height > 30 { expanded = false }
                }
            }
    }
}

/// A label/value row used inside the calculators' result cards.
struct CalcResultRow: View {
    let title: String
    let value: String
    var prominent: Bool = false

    init(_ title: String, _ value: String, prominent: Bool = false) {
        self.title = title
        self.value = value
        self.prominent = prominent
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(prominent ? .title3.weight(.bold) : .body)
        }
    }
}

/// An inline warning line (orange) used under the result rows.
struct CalcWarning: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
