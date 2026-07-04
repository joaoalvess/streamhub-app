import SwiftUI

/// Elenco e direção, alinhados ao canto inferior direito da window.
struct CastDirectionView: View {
    let cast: [MediaItem.Person]
    let directors: [MediaItem.Person]

    private var castNames: String {
        cast.prefix(3).map(\.name).formatted(.list(type: .and))
    }

    private var directorNames: String {
        directors.prefix(2).map(\.name).formatted(.list(type: .and))
    }

    var body: some View {
        if !castNames.isEmpty || !directorNames.isEmpty {
            VStack(alignment: .trailing, spacing: 4) {
                if !castNames.isEmpty {
                    Text("Estrelando \(castNames)")
                }
                if !directorNames.isEmpty {
                    Text("Direção \(directorNames)")
                }
            }
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 380, alignment: .trailing)
        }
    }
}
