import SwiftUI

enum ProfileEditorTarget: Identifiable {
    case create
    case edit(Profile)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let profile): profile.id.uuidString
        }
    }

    var profile: Profile? {
        if case .edit(let profile) = self { return profile }
        return nil
    }
}

private enum EditorFocus: Hashable {
    case name
    case save
}

struct ProfileEditorView: View {
    let target: ProfileEditorTarget
    @Environment(ProfileStore.self) private var profileStore
    @Environment(PlaybackProgressStore.self) private var progressStore: PlaybackProgressStore?
    @Environment(RecentSearchesStore.self) private var recentSearchesStore: RecentSearchesStore?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var avatarAsset: String?
    @State private var coverAsset: String
    @State private var confirmDelete = false
    @FocusState private var focus: EditorFocus?

    private static let formWidth: CGFloat = 460

    init(target: ProfileEditorTarget) {
        self.target = target
        if let profile = target.profile {
            _name = State(initialValue: profile.name)
            _avatarAsset = State(initialValue: profile.avatarAsset)
            _coverAsset = State(initialValue: profile.coverAsset ?? ProfileImageCatalog.defaultCover)
        } else {
            _name = State(initialValue: "")
            _avatarAsset = State(initialValue: ProfileImageCatalog.avatars.randomElement())
            _coverAsset = State(initialValue: ProfileImageCatalog.covers.randomElement() ?? ProfileImageCatalog.defaultCover)
        }
    }

    var body: some View {
        ZStack {
            backdrop

            HStack(alignment: .top, spacing: 64) {
                identityColumn
                    .frame(width: Self.formWidth)

                optionsColumn
            }
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.top, 64)
            .padding(.bottom, 40)
        }
        .defaultFocus($focus, target.profile == nil ? .name : .save)
        .alert("Excluir \"\(target.profile?.name ?? "")\"?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) { performDelete() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O progresso de reprodução deste perfil será apagado.")
        }
    }

    // Fundo = capa selecionada, atualizando ao vivo conforme a escolha.
    private var backdrop: some View {
        ZStack {
            Image(coverAsset)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .id(coverAsset)
                .transition(.opacity)

            Color.black.opacity(0.4).ignoresSafeArea()
            Theme.profileScrim.ignoresSafeArea()
            Theme.profileVignette.ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.35), value: coverAsset)
    }

    private var identityColumn: some View {
        VStack(spacing: 28) {
            Text(target.profile == nil ? "Novo Perfil" : "Editar Perfil")
                .font(Theme.Font.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 2)

            ProfileAvatarView(name: name, avatarAsset: avatarAsset, size: 200)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 8)

            TextField("Nome", text: $name)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .focused($focus, equals: .name)

            VStack(spacing: 16) {
                Button {
                    save()
                } label: {
                    Text("Salvar").frame(maxWidth: .infinity)
                }
                .disabled(trimmedName.isEmpty)
                .focused($focus, equals: .save)

                Button {
                    dismiss()
                } label: {
                    Text("Cancelar").frame(maxWidth: .infinity)
                }

                if target.profile != nil {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Text("Excluir Perfil").frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .focusSection()
    }

    private var optionsColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 44) {
                if !ProfileImageCatalog.avatars.isEmpty {
                    avatarSection
                }
                if !ProfileImageCatalog.covers.isEmpty {
                    coverSection
                }
            }
            .padding(.vertical, Theme.Metrics.focusHeadroom)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Avatar")
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 6),
                alignment: .leading,
                spacing: 28
            ) {
                AvatarOption(asset: nil, name: name, isSelected: avatarAsset == nil) {
                    avatarAsset = nil
                }
                ForEach(ProfileImageCatalog.avatars, id: \.self) { asset in
                    AvatarOption(asset: asset, name: name, isSelected: avatarAsset == asset) {
                        avatarAsset = asset
                    }
                }
            }
        }
    }

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Capa")
                .font(Theme.Font.cardTitle)
                .foregroundStyle(Theme.textSecondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3),
                alignment: .leading,
                spacing: 32
            ) {
                ForEach(ProfileImageCatalog.covers, id: \.self) { asset in
                    CoverOption(asset: asset, isSelected: coverAsset == asset) {
                        coverAsset = asset
                    }
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let profile = Profile(
            id: target.profile?.id ?? UUID(),
            name: trimmedName,
            avatarAsset: avatarAsset,
            coverAsset: coverAsset
        )
        profileStore.upsert(profile)
        dismiss()
    }

    private func performDelete() {
        guard let profile = target.profile else { return }
        profileStore.delete(profile)
        progressStore?.removeData(for: profile.id)
        recentSearchesStore?.removeData(for: profile.id)
        dismiss()
    }
}

private struct AvatarOption: View {
    let asset: String?
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(name: name, avatarAsset: asset, size: 150)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(.white, lineWidth: 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.06 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct CoverOption: View {
    let asset: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Image(asset)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(.white, lineWidth: 4)
                    }
                }
                .hoverEffect(.highlight)
        }
        .buttonStyle(.borderless)
    }
}

#Preview {
    ProfileEditorView(target: .create)
        .environment(ProfileStore())
        .preferredColorScheme(.dark)
}
