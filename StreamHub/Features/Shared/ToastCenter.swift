import Accessibility
import Observation
import SwiftUI

nonisolated struct Toast: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: String
    let systemImage: String?
}

@Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    init(duration: Duration = .seconds(2.5)) {
        self.duration = duration
    }

    func show(_ message: String, systemImage: String? = nil) {
        let toast = Toast(id: UUID(), message: message, systemImage: systemImage)
        current = toast
        AccessibilityNotification.Announcement(message).post()
        dismissTask?.cancel()
        dismissTask = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: toast.id)
        }
    }

    func dismiss(id: UUID) {
        guard current?.id == id else { return }
        current = nil
    }
}

struct ToastHost: ViewModifier {
    @Environment(ToastCenter.self) private var center: ToastCenter?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                ZStack {
                    if let toast = center?.current {
                        ToastView(toast: toast)
                            .id(toast.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, 60)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .animation(.easeInOut(duration: 0.3), value: center?.current)
            }
    }
}

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage = toast.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
            }
            Text(toast.message)
                .font(Theme.Font.cardTitle)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

extension View {
    func toastHost() -> some View {
        modifier(ToastHost())
    }
}
