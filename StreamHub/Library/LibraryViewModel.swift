import Foundation
import Observation

nonisolated struct LibraryEntry: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let year: Int?
    let runtimeMinutes: Int?
    let resumePositionSeconds: Int?
    let progress: Double?
    let posterURL: URL?
    let backdropURL: URL?
    let resolutionLabel: String?
    let audioLabel: String?

    init(item: JellyfinItem, base: URL?) {
        id = item.id
        name = item.name
        year = item.productionYear
        runtimeMinutes = item.runtimeMinutes
        resumePositionSeconds = item.positionSeconds
        if let percentage = item.userData?.playedPercentage, percentage > 0 {
            progress = min(1, max(0, percentage / 100))
        } else {
            progress = nil
        }
        if let base, let tag = item.primaryImageTag {
            posterURL = JellyfinAPI.primaryImageURL(base: base, itemId: item.id, tag: tag, maxWidth: 536)
        } else {
            posterURL = nil
        }
        if let base, let tag = item.backdropImageTag {
            backdropURL = JellyfinAPI.backdropImageURL(base: base, itemId: item.id, tag: tag, maxWidth: 1920)
        } else {
            backdropURL = nil
        }
        resolutionLabel = Self.resolutionBadge(streams: item.mediaStreams)
        audioLabel = Self.audioBadge(streams: item.mediaStreams)
    }

    nonisolated static func resolutionBadge(streams: [JellyfinMediaStream]?) -> String? {
        let heights = (streams ?? []).compactMap { $0.type == "Video" ? $0.height : nil }
        guard let height = heights.max(), height > 0 else { return nil }
        if height >= 2000 { return "4K" }
        if height >= 1000 { return "1080p" }
        if height >= 690 { return "720p" }
        return "SD"
    }

    nonisolated static func audioBadge(streams: [JellyfinMediaStream]?) -> String? {
        guard let streams else { return nil }
        let audioLanguages = streams.filter { $0.type == "Audio" }.compactMap(\.language)
        let hasPortugueseAudio = audioLanguages.contains(where: Self.isPortuguese)
        let hasForeignAudio = audioLanguages.contains { Self.isPortuguese($0) == false }
        if hasPortugueseAudio && hasForeignAudio { return "DUAL" }
        if hasPortugueseAudio { return "DUB" }
        let hasPortugueseSubtitle = streams.contains {
            $0.type == "Subtitle" && ($0.language.map(Self.isPortuguese) ?? false)
        }
        if hasPortugueseSubtitle { return "LEG" }
        return nil
    }

    nonisolated static func isPortuguese(_ language: String) -> Bool {
        let lowercased = language.lowercased()
        return lowercased.hasPrefix("por") || lowercased.hasPrefix("pob") || lowercased.hasPrefix("pt")
    }

    var startSeconds: Int? {
        guard let resumePositionSeconds, resumePositionSeconds >= 30 else { return nil }
        if let runtimeMinutes, runtimeMinutes > 0,
           Double(resumePositionSeconds) > Double(runtimeMinutes * 60) * 0.95 {
            return nil
        }
        return resumePositionSeconds
    }

    func sessionMetadata() -> NativeSessionMetadata {
        NativeSessionMetadata(
            subtitle: nil,
            synopsis: nil,
            artworkURL: backdropURL ?? posterURL,
            year: year,
            genres: [],
            runtimeMinutes: runtimeMinutes,
            ageRatingLabel: nil,
            ratingLabel: nil
        )
    }
}

nonisolated struct LibraryRow: Identifiable, Sendable {
    let id: String
    let title: String
    let isResume: Bool
    var entries: [LibraryEntry]
}

@Observable @MainActor
final class LibraryViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private static let resumeRowId = "resume"

    private(set) var phase: Phase = .loading
    private(set) var rows: [LibraryRow] = []

    private let api: JellyfinAPI
    private let baseProvider: () -> URL?
    private var hasLoaded = false

    init(
        api: JellyfinAPI = JellyfinAPI(),
        baseProvider: @escaping () -> URL? = { SecretsStore.shared.jellyfinBase }
    ) {
        self.api = api
        self.baseProvider = baseProvider
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await load()
    }

    func load() async {
        phase = .loading
        let api = self.api
        let base = baseProvider()
        do {
            let resumeTask = Task { (try? await api.resumeItems(limit: 20)) ?? [] }
            let latestTask = Task { (try? await api.latestItems(limit: 30)) ?? [] }
            let views = try await api.userViews()
            var viewRows: [(Int, LibraryRow)] = []
            await withTaskGroup(of: (Int, LibraryRow?).self) { group in
                for (index, view) in views.enumerated() {
                    group.addTask {
                        let items = (try? await api.items(parentId: view.id, limit: 50)) ?? []
                        guard !items.isEmpty else { return (index, nil) }
                        let row = LibraryRow(
                            id: view.id,
                            title: view.name,
                            isResume: false,
                            entries: items.map { LibraryEntry(item: $0, base: base) }
                        )
                        return (index, row)
                    }
                }
                for await (index, row) in group {
                    if let row {
                        viewRows.append((index, row))
                    }
                }
            }
            var loaded: [LibraryRow] = []
            let resumeEntries = await resumeTask.value.map { LibraryEntry(item: $0, base: base) }
            if !resumeEntries.isEmpty {
                loaded.append(LibraryRow(
                    id: Self.resumeRowId,
                    title: "Continuar assistindo",
                    isResume: true,
                    entries: resumeEntries
                ))
            }
            let latestEntries = Self.dedupedByTitle(await latestTask.value.map { LibraryEntry(item: $0, base: base) })
            if !latestEntries.isEmpty {
                loaded.append(LibraryRow(
                    id: "latest",
                    title: "Adicionados recentemente",
                    isResume: false,
                    entries: latestEntries
                ))
            }
            loaded.append(contentsOf: viewRows.sorted { $0.0 < $1.0 }.map(\.1))
            rows = loaded
            phase = .loaded
        } catch {
            if Self.isCancellation(error) {
                hasLoaded = false
                return
            }
            phase = .failed(Self.message(for: error))
        }
    }

    func refreshResume() async {
        guard phase == .loaded else { return }
        let base = baseProvider()
        let items = (try? await api.resumeItems(limit: 20)) ?? []
        let entries = items.map { LibraryEntry(item: $0, base: base) }
        if let index = rows.firstIndex(where: { $0.id == Self.resumeRowId }) {
            if entries.isEmpty {
                rows.remove(at: index)
            } else {
                rows[index].entries = entries
            }
        } else if !entries.isEmpty {
            rows.insert(LibraryRow(
                id: Self.resumeRowId,
                title: "Continuar assistindo",
                isResume: true,
                entries: entries
            ), at: 0)
        }
    }

    nonisolated static func dedupedByTitle(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        var seen: Set<String> = []
        return entries.filter { entry in
            let name = entry.name.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "pt_BR")
            )
            let key = "\(name)|\(entry.year.map(String.init) ?? "")"
            return seen.insert(key).inserted
        }
    }

    nonisolated static func message(for error: any Error) -> String {
        switch error {
        case JellyfinError.notConfigured:
            "Configure o Jellyfin no Secrets.plist para usar a Biblioteca."
        case JellyfinError.unauthorized:
            "Falha de autenticação no Jellyfin. Verifique usuário e senha."
        case JellyfinError.badStatus(let code):
            "O servidor Jellyfin retornou um erro (\(code))."
        case JellyfinError.decoding:
            "Resposta inesperada do servidor Jellyfin."
        default:
            "Servidor Jellyfin inacessível. Verifique a conexão."
        }
    }

    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if case JellyfinError.transport(let inner) = error {
            if inner is CancellationError { return true }
            return (inner as? URLError)?.code == .cancelled
        }
        return false
    }
}
