import Foundation
import Observation

@Observable
final class SeriesDetailViewModel {
    enum Phase: Equatable { case idle, loading, loaded, unavailable, failed }

    private(set) var phase: Phase = .idle
    private(set) var seasons: [SeasonGroup] = []
    private(set) var selectedSeasonIndex: Int = 0
    private(set) var detail: MetaDetail?

    var seasonTabs: [SeasonGroup] { seasons.filter { $0.number != 0 } }
    var specials: SeasonGroup? { seasons.first { $0.number == 0 } }

    var selectedSeason: SeasonGroup? {
        seasonTabs.indices.contains(selectedSeasonIndex) ? seasonTabs[selectedSeasonIndex] : nil
    }

    func load(item: MediaItem, provider: MetaProvider, store: PlaybackProgressStore?) async {
        phase = .loading
        let seriesId = PlaybackProgressStore.seriesKey(for: item) ?? item.contentId ?? ""
        do {
            let detail = try await provider.detail(for: item)
            self.detail = detail
            guard let detail, let videos = detail.videos, videos.count > 1 else {
                phase = .unavailable
                return
            }
            seasons = EpisodePlanner.seasons(
                from: videos,
                fallbackRuntimeMinutes: RuntimeParser.minutes(from: detail.runtime)
            )
            let next = EpisodePlanner.nextUnwatched(
                seasons: seasons,
                resume: resumeEntry(store: store, seriesId: seriesId),
                watched: store?.watchedVideoIds(seriesId: seriesId) ?? []
            )
            let defaultIndex = EpisodePlanner.defaultSeasonIndex(seasons: seasons, next: next)
            let defaultNumber = seasons.indices.contains(defaultIndex) ? seasons[defaultIndex].number : nil
            selectedSeasonIndex = defaultNumber.flatMap { number in
                seasonTabs.firstIndex { $0.number == number }
            } ?? 0
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed
        }
    }

    func selectSeason(_ index: Int) {
        guard seasonTabs.indices.contains(index) else { return }
        selectedSeasonIndex = index
    }

    func nextEpisode(store: PlaybackProgressStore?, seriesId: String) -> EpisodeItem? {
        EpisodePlanner.nextUnwatched(
            seasons: seasons,
            resume: resumeEntry(store: store, seriesId: seriesId),
            watched: store?.watchedVideoIds(seriesId: seriesId) ?? []
        )
    }

    func episodeAfter(_ episode: EpisodeItem) -> EpisodeItem? {
        EpisodePlanner.episodeAfter(episode, seasons: seasons)
    }

    func playLabel(store: PlaybackProgressStore?, seriesId: String) -> String {
        EpisodePlanner.playLabel(
            next: nextEpisode(store: store, seriesId: seriesId),
            resume: resumeEntry(store: store, seriesId: seriesId)
        )
    }

    func progress(for episode: EpisodeItem, store: PlaybackProgressStore?, seriesId: String) -> Double? {
        guard let resume = resumeEntry(store: store, seriesId: seriesId),
              resume.videoId == episode.videoId else { return nil }
        return resume.progress
    }

    func isWatched(_ episode: EpisodeItem, store: PlaybackProgressStore?, seriesId: String) -> Bool {
        store?.isWatched(seriesId: seriesId, videoId: episode.videoId) ?? false
    }

    private func resumeEntry(store: PlaybackProgressStore?, seriesId: String) -> ResumeEntry? {
        store?.entries.first { $0.contentId == seriesId }
    }
}
