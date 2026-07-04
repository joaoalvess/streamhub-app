import SwiftUI

/// Selos de qualidade DECORATIVOS e fixos (placeholder).
///
/// O addon de metadata não expõe qualidade de stream (4K, Dolby Vision,
/// Dolby Atmos, CC, AD) — esses atributos descrevem o arquivo/fonte, que só
/// será resolvido ao entrar em fullscreen, no futuro. Até lá, estes selos são
/// estáticos e não refletem a mídia real do título.
struct QualityBadgesView: View {
    private static let badges = ["4K", "Dolby Vision", "Dolby Atmos", "CC", "AD"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.textSecondary.opacity(0.5), lineWidth: 1.5)
                    }
            }
        }
    }
}
