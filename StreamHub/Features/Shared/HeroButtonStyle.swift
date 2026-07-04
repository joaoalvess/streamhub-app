import SwiftUI

struct HeroButtonStyle: ButtonStyle {
    enum Shape { case capsule, circle }
    var shape: Shape
    var isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        Group {
            switch shape {
            case .capsule:
                configuration.label
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black : Theme.textPrimary)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 18)
                    .modifier(HeroGlassBackground(isActive: isActive, shape: Capsule()))
            case .circle:
                configuration.label
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isActive ? Color.black : Theme.textPrimary)
                    .frame(width: 64, height: 64)
                    .modifier(HeroGlassBackground(isActive: isActive, shape: Circle()))
            }
        }
        .animation(.easeOut(duration: 0.18)) { view in
            view.scaleEffect(configuration.isPressed ? 1.04 : (isActive ? 1.08 : 1.0))
        }
    }
}

struct HeroGlassBackground<S: Shape>: ViewModifier {
    var isActive: Bool
    var shape: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Color.clear.glassEffect(.clear, in: shape)
                    shape.fill(Theme.fill).opacity(isActive ? 1 : 0)
                }
            }
    }
}
