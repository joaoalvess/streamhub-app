# Workstream B — Playback e UI de Séries/Episódios

Fases **F4–F9** do [roadmap](./README.md). Objetivo: séries (e episódios de anime) reproduzíveis fim a fim — meta com episódios, UI de temporadas/episódios na ficha, Play inteligente ("próximo não assistido"), progresso por episódio e Continue Watching correto.

Pré-requisitos vindos do workstream A (F2): `route(for:)` na forma final (séries sempre Infuse), guard temporário contra séries e `RuntimeParser` extraído.

---

## F4 — Camada de meta (`/meta/{type}/{id}.json`)

### Modelos novos — `StreamHub/Catalog/MetaModels.swift` (todos `nonisolated … Decodable, Sendable`)

```swift
nonisolated struct MetaResponse: Decodable, Sendable {
    let meta: MetaDetail?          // null se inexistente
}

nonisolated struct MetaDetail: Decodable, Sendable {
    let id: String                 // "tt0903747" | "mal:5114" (anime mantém prefixo)
    let type: String               // "movie" | "series"
    let name: String
    let description: String?
    let genres: [String]?
    let year: LenientString?       // reuso do LenientString existente
    let imdbRating: String?
    let runtime: String?           // "44min" — fallback de runtime por episódio
    let status: String?            // "Continuing" | "Ended"
    let poster: String?
    let background: String?
    let logo: String?
    let videos: [MetaVideo]?       // ausente em movie
    let behaviorHints: MetaBehaviorHints?
    let appExtras: AppExtras?      // CodingKey "app_extras"
    let imdbId: String?            // CodingKey "_imdbId"
}

nonisolated struct MetaVideo: Decodable, Sendable {
    let id: String                 // VERBATIM: "tt0903747:1:1" | "kitsu:3936:12" | "tt1355642:0:3"
    let title: String?
    let season: Int?               // 0 = especiais; nil → tratar como 1
    let episode: Int?
    let thumbnail: String?
    let overview: String?
    let released: String?          // ISO 8601
    let available: Bool?           // extensão AIOMetadata
    let runtime: LenientString?    // "43min" (string) ou número, conforme a fonte
}

nonisolated struct MetaBehaviorHints: Decodable, Sendable {
    let defaultVideoId: String?
    let hasScheduledVideos: Bool?
}
```

Nome `MetaVideo` (não `Video`/`Episode`): evita colisão com AVFoundation/SwiftUI e marca que é DTO do addon; o modelo de apresentação (F5) chama-se `EpisodeItem`.

### `MetadataAPI.meta(type:id:)` — `StreamHub/Catalog/MetadataAPI.swift`

```swift
func meta(type: String, id: String) async throws -> MetaDetail?
// GET {base}/meta/{type}/{id}.json — o ":" do id vai literal no path
```

Reusa o `get<T>` privado existente (base hardcoded + override Keychain).

### `MetaProvider` — `StreamHub/Catalog/MetaProvider.swift`

```swift
@Observable  // MainActor pelo default do projeto
final class MetaProvider {
    init(api: MetadataAPI = MetadataAPI())
    func detail(for item: MediaItem) async throws -> MetaDetail?
    nonisolated static func metaRequest(for item: MediaItem) -> (type: String, id: String)?
}
```

- **`metaRequest`** (puro, testável): id = `item.contentId` (fallback `item.imdbId`); type = `"series"` quando `kind == .series` OU `item.isAnime` (anime SEMPRE via `/meta/series/mal:{id}.json` — [../api/metadata/06-id-system.md](../api/metadata/06-id-system.md); o addon resolve internamente); `"movie"` só para filme não-anime.
- **Cache**: dicionário chave `"type|id"`, TTL 10 min + dedupe de in-flight com `Task` (mesmo padrão do `fetchStreams` do coordinator). Instância única injetada via `.environment` no `StreamHubApp`, junto ao `PlaybackCoordinator`.

### Testes — `StreamHubTests/MetaModelsTests.swift`

- Parse de série tt (recorte do tt0903747): 3 videos, season 0 primeiro no array, runtime string "43min" via `LenientString`.
- Parse de anime mal: ids MISTOS — especiais `tt1355642:0:1` + regulares `kitsu:3936:12` (sem season no id, com `season`/`episode` numéricos no objeto).
- `meta: null` → nil.
- `metaRequest`: série tt → ("series", tt…); anime mal:/kitsu: → ("series", "mal:…"); filme → ("movie", tt…).

---

## F5 — Modelo de apresentação (agrupamento e next-unwatched)

### Tipos — `StreamHub/Models/EpisodeModels.swift` (`nonisolated`, lógica pura)

```swift
nonisolated struct EpisodeItem: Identifiable, Hashable {
    let videoId: String            // MetaVideo.id VERBATIM — nunca reconstruído
    let season: Int
    let episode: Int
    let title: String              // fallback "Episódio \(episode)"
    let overview: String?
    let thumbnailURL: URL?
    let releasedAt: Date?
    let runtimeMinutes: Int?
    let isReleased: Bool           // available ?? (releasedAt.map { $0 <= now } ?? true)
    var id: String { videoId }
    var code: String { "T\(season)E\(episode)" }
}

nonisolated struct SeasonGroup: Identifiable, Hashable {
    let number: Int                          // 0 = especiais
    let episodes: [EpisodeItem]              // ordenados por episode
    var id: Int { number }
    var label: String { number == 0 ? "Especiais" : "Temporada \(number)" }
}

nonisolated enum EpisodePlanner {
    static func seasons(from videos: [MetaVideo],
                        fallbackRuntimeMinutes: Int?,
                        now: Date = .now) -> [SeasonGroup]
    static func nextUnwatched(seasons: [SeasonGroup],
                              resume: ResumeEntry?,
                              watched: Set<String>) -> EpisodeItem?
    static func episodeAfter(_ episode: EpisodeItem, seasons: [SeasonGroup]) -> EpisodeItem?
    static func defaultSeasonIndex(seasons: [SeasonGroup], next: EpisodeItem?) -> Int
    static func playLabel(next: EpisodeItem?, resume: ResumeEntry?) -> String
}
```

### Regras (definitivas)

- **Agrupamento**: por `season` (nil → 1), temporadas ascendentes com **season 0 ("Especiais") movido para o FIM** (a API entrega season 0 primeiro — reordenar sempre). Episódios por `episode` ascendente.
- **Ordem canônica de reprodução** (usada por `nextUnwatched` E `episodeAfter`): temporadas não-especiais concatenadas, **apenas episódios lançados**; especiais EXCLUÍDOS do avanço automático (reproduzíveis só manualmente).
- **`episodeAfter`** (correção da revisão): navega a ordem canônica — o último episódio regular retorna `nil` (nunca aponta para especial nem para episódio não lançado). É ela que alimenta o `next` pré-calculado da sessão (F6): sem essa regra, o card do Continue Watching "avançaria" para um especial ao completar a última temporada.
- **Temporada default**: a do `nextUnwatched`; sem progresso → primeira não-especial; só especiais → especiais.
- **Não lançados** (`isReleased == false`): no fim da fileira da temporada, atenuados, legenda "Estreia em {data}", **focáveis porém não reproduzíveis** (select no-op) — desabilitar foco quebraria a navegação horizontal do tvOS.
- **Runtime ausente**: fallback = runtime da série (`MetaDetail.runtime` via `RuntimeParser`); se ainda nil → sem barra de progresso e episódio **nunca auto-completa** (só resume por posição).
- **next-unwatched** (4 passos):
  1. `resume.videoId` casa com episódio lançado e `resume.progress < 0.92` → retoma esse episódio.
  2. `resume.videoId` não existe mais no meta (meta mudou) → casa por `(resume.season, resume.episode)`; falhou → passo 3.
  3. Primeiro episódio lançado, na ordem canônica, cujo `videoId ∉ watched`.
  4. Tudo assistido ou sem histórico → primeiro episódio lançado (T1E1).
- **`playLabel`**: retomando → `"Continuar T2E5"`; próximo novo → `"Reproduzir T2E5"`; fallback → `"Reproduzir T1E1"`; sem episódios → `"Reproduzir"` (desabilitado).

### `SeriesDetailViewModel` — `StreamHub/Features/MediaWindow/SeriesDetailViewModel.swift`

```swift
@Observable
final class SeriesDetailViewModel {
    enum Phase: Equatable { case idle, loading, loaded, unavailable, failed }
    private(set) var phase: Phase
    private(set) var seasons: [SeasonGroup]
    private(set) var selectedSeasonIndex: Int
    var selectedSeason: SeasonGroup? { get }

    func load(item: MediaItem, provider: MetaProvider) async
    func cycleSeason()                                          // wrap-around
    func nextEpisode(store: PlaybackProgressStore?, seriesId: String) -> EpisodeItem?
    func episodeAfter(_ episode: EpisodeItem) -> EpisodeItem?
    func playLabel(store: PlaybackProgressStore?, seriesId: String) -> String
    func progress(for episode: EpisodeItem, store: PlaybackProgressStore?, seriesId: String) -> Double?
    func isWatched(_ episode: EpisodeItem, store: PlaybackProgressStore?, seriesId: String) -> Bool
}
```

`phase == .unavailable` quando meta nil ou `videos` vazio/1 item (anime single — ver edge cases).

### Testes — `StreamHubTests/EpisodePlannerTests.swift`

- Agrupamento: seasons 0,1,2 desordenadas → especiais por último; ordenação interna por episode.
- Ids mistos de anime preservados verbatim em `EpisodeItem.videoId`.
- `available: false` / `released` futuro → `isReleased == false`.
- Runtime: "43min" → 43; ausente → fallback da série; ambos ausentes → nil.
- next-unwatched: (a) sem histórico → T1E1; (b) resume parcial → retoma; (c) resume completo → próximo; (d) fim de temporada → T(n+1)E1; (e) tudo assistido → T1E1; (f) videoId órfão → casa por (season,episode); (g) especiais ignorados.
- `episodeAfter`: meio da temporada → próximo; fim da temporada → T(n+1)E1; último regular → **nil** (mesmo existindo especiais/não-lançados depois).
- `playLabel` para os 3 casos.

---

## F6 — Progresso por episódio (store v2)

### Decisão de chave: UMA entrada por série, com campos de episódio embutidos

Chave da entrada continua sendo uma por título; Continue Watching = 1 card por série "de graça" (upsert deduplica), cap de 20 = 20 títulos. Marcação individual de "assistido" vai em histórico separado (abaixo).

**Chave preferencial `_imdbId` com fallback `contentId`** (correção da revisão): a mesma série vinda da aba Animes (`mal:…`) e do acervo Crunchyroll (`tt…`) geraria históricos separados se a chave fosse só `contentId`. Introduzir `seriesKey(for item:) = item.imdbId ?? item.contentId` e usar consistentemente em resume + watched.

### `ResumeEntry` v2 — campos NOVOS, todos opcionais (sem migração)

```swift
let mediaKind: String?     // "movie" | "series" | "anime"; nil = legado → .movie
var videoId: String?       // id VERBATIM do episódio corrente
var season: Int?
var episode: Int?
var episodeTitle: String?
var episodeCode: String? { /* season/episode → "T2E5" */ }   // computed
```

`positionSeconds`/`runtimeMinutes` passam a se referir ao episódio corrente quando `videoId != nil`. A key `"playback.resume.v1.<uuid>"` NÃO muda — v2 é aditivo: JSON v1 existente decodifica com os campos novos nil.

### Sessão com snapshot completo (correção CRÍTICA da revisão)

O mecanismo atual (`previousPosition: Int?` + `registerSession` semeando `optimistic.positionSeconds = position(for: contentId)`) corrompe a entrada ao trocar de episódio: ao dar play no E2, o card mostraria E2 com a posição do E1; e `discardSession` restauraria o episódio NOVO com posição antiga. Correção:

- `SessionRecord.previousEntry: ResumeEntry?` — **snapshot completo** da entrada anterior (substitui `previousPosition`; campo opcional → sessões v1 persistidas decodificam).
- `registerSession` zera a posição otimista quando `entry.videoId != entradaCorrente.videoId` (episódio novo começa do zero; mesmo episódio mantém posição para resume).
- `discardSession` restaura `previousEntry` inteiro (ou remove, se não havia).

### Contexto de episódio na sessão + histórico de assistidos

```swift
nonisolated struct EpisodeSessionContext: Codable, Hashable {
    let seriesId: String            // seriesKey (imdbId ?? contentId)
    let videoId: String
    let season: Int
    let episode: Int
    let next: NextEpisodeRef?       // pré-calculado pela UI no momento do play (episodeAfter)
}
nonisolated struct NextEpisodeRef: Codable, Hashable {
    let videoId: String; let season: Int; let episode: Int
    let title: String?; let runtimeMinutes: Int?
}

// PlaybackProgressStore — API nova:
func registerSession(videoURL: String, entry: ResumeEntry, episodeContext: EpisodeSessionContext?)
func watchedVideoIds(seriesId: String) -> Set<String>
func isWatched(seriesId: String, videoId: String) -> Bool
func markWatched(seriesId: String, videoId: String)
```

- Histórico: `[String: WatchedRecord]` (`WatchedRecord { videoIds: Set<String>, updatedAt: Date }`), persistido por perfil em `"playback.watched.v1.<uuid>"`, cap **40 séries** (poda pela `updatedAt` mais antiga). `removeData(for:)` e `setActiveProfile` passam a cobrir essa key.
- **`applyCallback` com episódio** (threshold 0.92 por episódio, mesmo valor de filmes):
  - Completo + `context.next != nil` → `markWatched(videoId)` + upsert da entrada apontando o PRÓXIMO (`videoId/season/episode/episodeTitle/runtimeMinutes` do next, `positionSeconds = 0`) — o card do CW anda sozinho.
  - Completo + `next == nil` (último episódio lançado) → `markWatched` + `remove` da entrada — a série sai do CW. **Decisão registrada**: série "Continuing" não ressurge no CW quando um episódio novo estreia (o watched preserva o estado; o usuário reencontra a série pelo catálogo e o Play inteligente retoma do lugar certo). Alternativa "entrada aguardando episódio" fica anotada como possível melhoria futura.
  - Incompleto → upsert normal com a posição.
- Cap de 20 entradas de resume: inalterado.

### Testes — ampliar `StreamHubTests/PlaybackProgressStoreTests.swift`

- Fixture JSON v1 (sem campos novos) → entrada válida com `videoId == nil`.
- Callback de episódio incompleto → posição atualizada.
- Callback completo com `next` → entrada aponta próximo com posição 0 + anterior no watched.
- Callback completo sem `next` → entrada removida + marcado assistido.
- `registerSession` de episódio DIFERENTE do corrente → posição otimista zero (não herda a do episódio anterior).
- `discardSession` restaura o snapshot do episódio anterior (entry completa, não só posição).
- Watched: cap de 40 séries poda a mais antiga; isolamento por perfil.

---

## F7 — PlaybackCoordinator: play de episódios

`route(for:)` já está na forma final desde a F2 — esta fase não toca em roteamento.

### Mudanças em `StreamHub/Playback/PlaybackCoordinator.swift`

```swift
// API nova (a play(item:mode:) existente permanece para filmes e anime "single"):
func play(item: MediaItem, episode: EpisodeItem, next: EpisodeItem?, mode: PlaybackMode) async

// Helpers nonisolated static (testáveis):
nonisolated static func streamRequest(videoId: String, isAnime: Bool)
    -> (type: String, profile: StreamProfile?)
nonisolated static func infuseFilename(item: MediaItem, episode: EpisodeItem, filename: String?) -> String
```

**Tabela do `streamRequest`** (id sempre VERBATIM):

| Prefixo do videoId | type | profile |
|---|---|---|
| `kitsu:` / `mal:` / `anilist:` | `anime` | `.anime` |
| `tt…` com `isAnime == true` (especial de anime) | `series` | `.anime` |
| `tt…` série normal | `series` | nil → `StreamProfile(mode:)` (Dub→casual, Leg→cinema; Best → `.enhancedUnavailable`) |

> ⚠️ **Verificação ao vivo nesta fase**: confirmar que o servidor do perfil anime responde à rota `series` para especiais (`/stream/series/tt…:0:E.json`). Se retornar vazio, fallback documentado: refazer com o perfil do modo (casual/cinema).

- **`playEpisodeViaInfuse`** (privado): `fetchStreams` atual já serve (cache keyed `profile|type|id`); primeiro stream jogável (contrato first-result); `resumePosition` nova assinatura `resumePosition(seriesId:videoId:runtimeMinutes:)` — só resume se `entry.videoId == episode.videoId`; `registerSession(videoURL:entry:episodeContext:)` com `ResumeEntry` v2 completo (mediaKind, videoId, season, episode, episodeTitle, runtime DO EPISÓDIO) e `next` vindo da view (`episodeAfter`).
- **`infuseFilename`**: `"Breaking Bad S01E01.mkv"` — `String(format: "S%02dE%02d")`, extensão pelo whitelist atual.
- **Seletor Dub/Leg para séries: SIM** (séries não-anime; séries sempre roteiam Infuse, então o seletor é sempre aplicável). Episódios kitsu:/mal: ignoram o modo (perfil anime) — seletor oculto, como hoje.
- **Infuse/sessões: sem mudança no casamento** — sessão é keyed pela URL do stream e cada episódio tem URL distinta; o `x-success (lastPlayedUrl)` já casa o episódio certo. Exceção teórica aceita: packs multi-episódio num arquivo único (progresso cai no episódio da sessão).
- Erro novo: `PlaybackError.noEpisodes` — "Nenhum episódio disponível para esta série.".

### Testes

- `StreamHubTests/PlaybackRoutingTests.swift` (novo): tabela do `streamRequest` (3 linhas acima); regressão da matriz de rota da F2.
- `StreamHubTests/InfuseURLTests.swift` (ampliar): filename `"Dark S03E08.mkv"`, zero-padding, extensão preservada/normalizada.

---

## F8 — UI: seção de episódios na MediaWindow

Reverte o guard temporário da F2 (séries passam a reproduzir SOMENTE pelo caminho novo com episódio resolvido — a view resolve, o coordinator não adivinha).

### Hierarquia de views — `StreamHub/Features/MediaWindow/`

```
MediaWindowView (existente)
└─ fullscreen: ScrollView(.vertical)                ← só quando o item tem episódios
   ├─ "página 1": WindowInfoOverlay (existente)     .containerRelativeFrame(.vertical)
   └─ EpisodesSectionView (novo)
      ├─ header: Text("Episódios") + SeasonSelectorButton (novo)
      └─ ScrollView(.horizontal) → LazyHStack de EpisodeCardView (novo)
```

- **Integração**: `MediaWindowView` ganha `@State private var seriesModel = SeriesDetailViewModel()` + `@Environment(MetaProvider.self)`; `.task(id: centerIndex)` dispara `seriesModel.load` quando `item.kind == .series || item.isAnime`. Modo window intocado (carrossel); em fullscreen com `phase == .loaded`, o overlay é hospedado num scroll vertical com a seção de episódios abaixo (padrão hero+fileiras da `HomeView`; `scrollClipDisabled` + `focusSection()` como em `ContinueWatchingRowView`). Filmes/anime single: layout atual intocado.
- **Navegação**: window → fullscreen (foco no Play) → ↓ da CTA row → shelf de episódios → select no card → play → callback Infuse via `onOpenURL`. Back: episódios → CTA (scroll ao topo) → window → dismiss (`onExitCommand` atual cobre).
- **`WindowFocus`** (enum de foco em `WindowInfoOverlay.swift:3`): novos cases `.season` e `.episode(Int)`.

### `SeasonSelectorButton` — controle compacto que CICLA

Botão capsule com `HeroButtonStyle`, label `"Temporada 2"`/`"Especiais"`, clique avança com wrap-around — idêntico à convenção Dub/Leg/Best. Trocar de temporada reseta o scroll da shelf ao E1. *Anotação pós-MVP (revisão): para séries longas (20+ temporadas) o ciclo é penoso — considerar long-press abrindo lista; não bloqueia esta fase.*

### `EpisodeCardView`

```swift
struct EpisodeCardView: View {
    let episode: EpisodeItem
    let progress: Double?      // nil oculta a barra
    let isWatched: Bool
    var onSelect: () -> Void
}
```

- Lockup nativo (convenção do projeto): `Button(.borderless)` + composite com `hoverEffect(.highlight)`; thumbnail 16:9 em `Theme.Size.wideCardWidth/Height` (380×214); `clipShape` com `Theme.Radius.card`.
- Sobre a imagem: barra de progresso na base (extrair o `ProgressBar` privado de `ContinueWatchingCardView` para `Features/Shared/MediaProgressBar.swift` e reusar); badge `checkmark.circle.fill` quando `isWatched`; thumbnail ausente → `Theme.bgElevated` + número grande do episódio.
- Abaixo da imagem (fora do foco): linha 1 `"E5 · Título"` (lineLimit 1); linha 2 sinopse (lineLimit 2, `Theme.Font.meta`, textSecondary) + runtime `"43min"`.
- Não lançado: opacidade 0.5, sem barra, legenda `"Estreia {dd 'de' MMM}"` no lugar do runtime; `onSelect` no-op.

### Play inteligente na CTA row

- `playLabel(for:)`: séries/anime-com-episódios → `seriesModel.playLabel` (`"Continuar T2E5"` / `"Reproduzir T1E1"`). Enquanto o meta carrega, se `ResumeEntry.videoId` existir, o label deriva da entrada (offline-friendly); senão "Reproduzir" desabilitado até `phase != .loading`.
- `play(_:)`: séries → resolve `nextEpisode` + `episodeAfter(next)` e chama `coordinator.play(item:episode:next:mode:)`. Atalho: meta falhou mas há `resume.videoId` → reproduz direto da entrada (constrói `EpisodeItem` mínimo, `next: nil`).
- `showsModeSelector(for:)` → `route == .infuse && !item.isAnime && (kind == .movie || kind == .series)`.
- Sem episódios (`phase == .unavailable` com 0 videos): shelf oculta; Play tenta `behaviorHints.defaultVideoId`; nil → `state = .failed(.noEpisodes)`.

*(Sem testes unitários de view; a lógica está em F5/F6/F7.)*

---

## F9 — Continue Watching para séries

- **Onde aparece**: abas Filmes, Séries e Animes — a MESMA fileira global, sem filtro por kind (padrão Netflix). Implementação: ligar `showsContinueWatching = true` nos presets `series`/`animes` de `HomeConfiguration` (a F1 já trocou o teste hardcoded por `config.showsContinueWatching` — NÃO reintroduzir teste por tag). Abas de canal ficam sem a fileira (decisão do workstream A §5).
- **Tocar no card abre o DETALHE** (comportamento atual via `router.open`), não toca direto: o detalhe concentra seletor de modo, erros e a lista de episódios, e o Play de lá já diz "Continuar T2E5".
- `ContinueWatchingRowView.swift` — `MediaItem(entry:)`: `kind: MediaItem.Kind(rawValue: entry.mediaKind ?? "movie") ?? .movie` (fim do hardcode); `episodeLabel`: séries → `"T2E5 · Restam 17 min"` (`episodeCode` + `remainingLabel`).
- `PlaybackCoordinator.resumeEntry(for:…)` (caminho de filmes) passa a gravar `mediaKind: item.kind.rawValue`.
- Card cujo meta mudou: renderiza 100% da entrada (self-contained); ao abrir o detalhe, o passo 2 do next-unwatched (casar por season/episode) resolve o videoId órfão.

---

## Edge cases (consolidado)

| Caso | Comportamento |
|---|---|
| Meta `null` / série sem `videos` | Shelf oculta; Play → `defaultVideoId` ou erro `.noEpisodes` |
| `Continuing` + `hasScheduledVideos` | Episódios futuros visíveis bloqueados com data; temporadas só-futuras aparecem (tudo bloqueado) |
| Season 0 (especiais) | Grupo "Especiais" por ÚLTIMO; nunca default; fora do auto-avanço; reproduzível manualmente |
| Anime 1 episódio / filme de anime | `videos.count <= 1` → `phase = .unavailable`; fluxo atual de play single (contentId direto, perfil anime) intocado |
| Ids mistos no mesmo anime (tt especiais + kitsu regulares) | `streamRequest` decide type POR videoId; perfil sempre anime |
| Entrada de CW com videoId órfão (meta mudou) | Fallback por (season, episode) → senão primeiro não-assistido |
| Runtime de episódio ausente | Fallback runtime da série; senão sem barra e sem auto-conclusão |
| Meta indisponível (rede) ao abrir detalhe | Play direto pela `ResumeEntry` se houver `videoId`; senão failed com retry na shelf |
| Série Continuing completada até o último episódio lançado | Sai do CW e não ressurge sozinha (decisão registrada na F6) |

---

## Arquivos por fase

**F4 (criar):** `StreamHub/Catalog/MetaModels.swift`, `StreamHub/Catalog/MetaProvider.swift`, `StreamHubTests/MetaModelsTests.swift` · **(modificar):** `StreamHub/Catalog/MetadataAPI.swift` (+`meta(type:id:)`), `StreamHub/StreamHubApp.swift` (injetar `MetaProvider`).

**F5 (criar):** `StreamHub/Models/EpisodeModels.swift`, `StreamHub/Features/MediaWindow/SeriesDetailViewModel.swift`, `StreamHubTests/EpisodePlannerTests.swift`.

**F6 (modificar):** `StreamHub/Playback/PlaybackProgressStore.swift` (ResumeEntry v2, snapshot `previousEntry`, EpisodeSessionContext, watched store, applyCallback com avanço, `seriesKey`), `StreamHubTests/PlaybackProgressStoreTests.swift`.

**F7 (modificar):** `StreamHub/Playback/PlaybackCoordinator.swift` (`play(item:episode:next:mode:)`, `streamRequest`, `infuseFilename` de episódio, `resumePosition` por videoId, `.noEpisodes`), `StreamHubTests/InfuseURLTests.swift` · **(criar):** `StreamHubTests/PlaybackRoutingTests.swift`.

**F8 (criar):** `StreamHub/Features/MediaWindow/EpisodesSectionView.swift`, `StreamHub/Features/MediaWindow/EpisodeCardView.swift`, `StreamHub/Features/MediaWindow/SeasonSelectorButton.swift`, `StreamHub/Features/Shared/MediaProgressBar.swift` · **(modificar):** `StreamHub/Features/MediaWindow/MediaWindowView.swift` (scroll fullscreen, seriesModel, playLabel/play/showsModeSelector, reverte guard da F2), `StreamHub/Features/MediaWindow/WindowInfoOverlay.swift` (novos cases em `WindowFocus`), `StreamHub/Features/Home/ContinueWatchingCardView.swift` (usar MediaProgressBar).

**F9 (modificar):** `StreamHub/Catalog/HomeConfiguration.swift` (presets com CW true), `StreamHub/Features/Home/ContinueWatchingRowView.swift` (kind/labels), `StreamHub/Playback/PlaybackCoordinator.swift` (resumeEntry com mediaKind).

*(Todos os arquivos novos entram no target StreamHub / StreamHubTests no `project.pbxproj`.)*
