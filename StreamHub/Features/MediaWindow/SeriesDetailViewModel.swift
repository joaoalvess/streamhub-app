import Foundation
import Observation

@Observable
final class SeriesDetailViewModel {
    enum Phase: Equatable { case idle, loading, loaded, unavailable, failed }

    private(set) var phase: Phase = .idle
    private(set) var seasons: [SeasonGroup] = []
    private(set) var seasonTabs: [SeasonGroup] = []
    private(set) var specials: SeasonGroup?
    private(set) var selectedSeasonIndex: Int = 0
    private(set) var detail: MetaDetail?

    @ObservationIgnored private var timeline = EpisodeTimeline(seasons: [])
    @ObservationIgnored private var progressCache: (seriesId: String, value: SeriesProgress)?

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
            let timeline = await EpisodePlanner.timeline(
                from: videos,
                fallbackRuntimeMinutes: RuntimeParser.minutes(from: detail.runtime)
            )
            guard !Task.isCancelled else { return }
            apply(timeline)
            let next = nextEpisode(store: store, seriesId: seriesId)
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
        seriesProgress(store: store, seriesId: seriesId).next
    }

    func episodeAfter(_ episode: EpisodeItem) -> EpisodeItem? {
        timeline.episodeAfter(episode)
    }

    func position(of episode: EpisodeItem) -> Int? {
        timeline.position(of: episode)
    }

    func playLabel(store: PlaybackProgressStore?, seriesId: String) -> String {
        let progress = seriesProgress(store: store, seriesId: seriesId)
        return EpisodePlanner.playLabel(next: progress.next, resume: progress.resume)
    }

    func seriesProgress(store: PlaybackProgressStore?, seriesId: String) -> SeriesProgress {
        let resume = store?.entries.first { $0.contentId == seriesId }
        let watched = store?.watchedVideoIds(seriesId: seriesId) ?? []
        if let cached = progressCache,
           cached.seriesId == seriesId,
           cached.value.resume == resume,
           cached.value.watched == watched {
            return cached.value
        }
        let value = SeriesProgress(
            resume: resume,
            watched: watched,
            next: timeline.nextUnwatched(resume: resume, watched: watched)
        )
        progressCache = (seriesId, value)
        return value
    }

    private func apply(_ timeline: EpisodeTimeline) {
        self.timeline = timeline
        progressCache = nil
        seasons = timeline.seasons
        seasonTabs = timeline.seasons.filter { $0.number != 0 }
        specials = timeline.seasons.first { $0.number == 0 }
    }
}
