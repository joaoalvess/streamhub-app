import SwiftUI

private enum StageFocus: Hashable {
    case profile(UUID)
    case newProfile
    case manage
}

struct ProfileSelectionView: View {
    @Environment(ProfileStore.self) private var profileStore
    @State private var isEditing = false
    @State private var editorTarget: ProfileEditorTarget?
    @State private var stageName = ""
    @State private var stageCover = ProfileImageCatalog.defaultCover
    @FocusState private var focus: StageFocus?

    private static let maxProfiles = 6

    var body: some View {
        ZStack {
            StageBackdrop(cover: stageCover)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.Font.profileEyebrow)
                    .kerning(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                Text(stageName)
                    .font(Theme.Font.profileName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: stageName)
                    .padding(.top, 8)

                avatarRow
                    .padding(.top, 36)
            }
            .padding(.horizontal, Theme.Metrics.edgeH)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .defaultFocus($focus, defaultFocusTarget)
        .onExitCommand(perform: isEditing ? { isEditing = false } : nil)
        .onAppear { syncStage() }
        .onChange(of: focus) { syncStage() }
        .onChange(of: isEditing) { syncStage() }
        .onChange(of: profileStore.profiles) { syncStage() }
        .onChange(of: profileStore.profiles.isEmpty) { _, empty in
            if empty {
                isEditing = false
            }
        }
        .fullScreenCover(item: $editorTarget) { target in
            ProfileEditorView(target: target)
        }
    }

    private var avatarRow: some View {
        HStack(spacing: Theme.Metrics.cardSpacing) {
            ForEach(profileStore.profiles) { profile in
                ProfileAvatarCard(
                    profile: profile,
                    isEditing: isEditing,
                    focus: $focus
                ) {
                    if isEditing {
                        editorTarget = .edit(profile)
                    } else {
                        profileStore.select(profile)
                    }
                }
            }
            if profileStore.profiles.count < Self.maxProfiles {
                NewProfileCard(focus: $focus) { editorTarget = .create }
            }

            Spacer(minLength: Theme.Metrics.cardSpacing)

            if !profileStore.profiles.isEmpty {
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "gearshape.fill")
                }
                .buttonStyle(HeroButtonStyle(shape: .circle, isActive: focus == .manage))
                .focused($focus, equals: .manage)
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    private var defaultFocusTarget: StageFocus {
        if let first = profileStore.profiles.first {
            return .profile(first.id)
        }
        return .newProfile
    }

    private var title: String {
        if profileStore.profiles.isEmpty {
            return "Crie seu primeiro perfil"
        }
        return isEditing ? "Selecione um perfil para editar" : "Quem está assistindo?"
    }

    private func syncStage() {
        var target = focus ?? defaultFocusTarget
        if case .profile(let id) = target,
           !profileStore.profiles.contains(where: { $0.id == id }) {
            target = defaultFocusTarget
        }

        switch target {
        case .profile(let id):
            guard let profile = profileStore.profiles.first(where: { $0.id == id }) else { return }
            stageName = profile.name
            stageCover = profile.coverAsset ?? ProfileImageCatalog.defaultCover
        case .newProfile:
            stageName = "Novo Perfil"
            stageCover = ProfileImageCatalog.defaultCover
        case .manage:
            stageName = isEditing ? "Concluir" : "Gerenciar Perfis"
        }
    }
}

private struct StageBackdrop: View {
    let cover: String
    @State private var kenBurns = false

    var body: some View {
        ZStack {
            ZStack {
                Image(cover)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .id(cover)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: cover)
            .scaleEffect(kenBurns ? 1.06 : 1.0)
            .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: kenBurns)

            Theme.profileStageScrim.ignoresSafeArea()
            Theme.profileVignette.ignoresSafeArea()
        }
        .onAppear { kenBurns = true }
    }
}

private struct ProfileAvatarCard: View {
    let profile: Profile
    let isEditing: Bool
    @FocusState.Binding var focus: StageFocus?
    let action: () -> Void

    private var isFocused: Bool { focus == .profile(profile.id) }

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(
                name: profile.name,
                avatarAsset: profile.avatarAsset,
                size: Theme.Size.profileCircle
            )
            .overlay {
                if isEditing {
                    ZStack {
                        Circle().fill(.black.opacity(0.45))
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Theme.textPrimary, .black.opacity(0.55))
                    }
                }
            }
            .profileCircleFocus(isFocused, scale: 1.12)
        }
        .buttonStyle(StageCircleButtonStyle())
        .focused($focus, equals: .profile(profile.id))
    }
}

private struct NewProfileCard: View {
    @FocusState.Binding var focus: StageFocus?
    let action: () -> Void

    private var isFocused: Bool { focus == .newProfile }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.bgElevated.opacity(0.55))
                Circle().strokeBorder(Theme.cardStroke, lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(isFocused ? Theme.textPrimary : Theme.textSecondary)
            }
            .frame(width: Theme.Size.profileCircle, height: Theme.Size.profileCircle)
            .profileCircleFocus(isFocused, scale: 1.12)
        }
        .buttonStyle(StageCircleButtonStyle())
        .focused($focus, equals: .newProfile)
    }
}

/// Estilo neutro: o foco visual é o anel circular do profileCircleFocus,
/// então o botão só repassa o conteúdo, sem o highlight retangular do sistema.
private struct StageCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    ProfileSelectionView()
        .environment(ProfileStore())
        .preferredColorScheme(.dark)
}
