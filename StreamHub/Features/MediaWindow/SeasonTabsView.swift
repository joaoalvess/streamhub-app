import SwiftUI

struct SeasonTabsView: View {
    let seasons: [SeasonGroup]
    let selectedIndex: Int
    var focus: FocusState<WindowFocus?>.Binding
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(seasons.enumerated()), id: \.element.id) { index, season in
                    Button(action: { onSelect(index) }) {
                        Text(season.label)
                    }
                    .buttonStyle(SeasonTabStyle(
                        isFocused: focus.wrappedValue == .season(index),
                        isSelected: index == selectedIndex
                    ))
                    .focused(focus, equals: .season(index))
                }
            }
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus(focus, .season(selectedIndex), priority: .userInitiated)
    }
}

private struct SeasonTabStyle: ButtonStyle {
    var isFocused: Bool
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(isFocused ? Color.black : (isSelected ? Theme.textPrimary : Theme.textSecondary))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background {
                Capsule().fill(isFocused ? Theme.fill : (isSelected ? Color.white.opacity(0.25) : Color.clear))
            }
            .animation(.easeOut(duration: 0.18)) { view in
                view.scaleEffect(configuration.isPressed ? 1.04 : (isFocused ? 1.08 : 1.0))
            }
    }
}
