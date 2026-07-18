# Roadmap de Implementação — Serviços de Streaming + Séries

Plano de execução para os dois workstreams que faltam para o StreamHub ficar completo:

- **Workstream A — Abas de serviços** ([01-servicos-streaming.md](./01-servicos-streaming.md)): transformar as 11 abas de "Canais" (hoje `ComingSoonView`) em Homes completas por serviço (Netflix, HBO Max, Disney+, Prime Video, Apple TV+, Paramount+, Hulu, Discovery+, Crunchyroll, Claro Video, Globoplay).
- **Workstream B — Playback de séries** ([02-series-playback.md](./02-series-playback.md)): tornar séries (e episódios de anime) reproduzíveis fim a fim — meta com episódios, UI de temporadas/episódios, Play inteligente, progresso por episódio e Continue Watching correto.

Este roadmap foi desenhado a partir do código real, dos docs de contrato (`docs/api/`, `docs/addons/`, `docs/player/`) e de verificações ao vivo do addon feitas em 2026-07-11. Passou por revisão técnica cruzada; as correções apontadas já estão incorporadas nas fases.

---

## Estado atual

**Funciona (filmes, fim a fim):** catálogo aiometadata (`manifest?tag=` + `catalog/{type}/{id}.json`) → detalhe (`MediaWindowView`) → resolução de stream por perfil server-side (AIOStreams cinema/casual/anime, contrato first-result) → deep link Infuse com x-callback → resume/Continue Watching por perfil de usuário.

**Não funciona:**

| Problema | Causa raiz |
|---|---|
| 11 abas de Canais mortas | `RootView.destination(for:)` só liga filmes/series/animes; `MenuSection` e `StreamingService` são enums paralelos sem mapeamento |
| Filtro de catálogo não serve para tags de serviço | `HomeViewModel` filtra `$0.type == tag`; tags de serviço retornam types mistos (`movie`+`series`+núcleo) |
| Séries não reproduzem | Guard em `PlaybackCoordinator.play` (`kind == .movie \|\| isAnime`); sem `MetadataAPI.meta()`, sem modelos de episódio, sem UI de temporadas |
| Progresso é só de filme | `ResumeEntry` sem season/episode; Continue Watching hardcoda `kind: .movie` e só aparece na aba Filmes |
| Heroes de Séries/Animes inválidos | `tmdb.trending_series` e `mal.season_top_anime` não existem no manifest (fallback silencioso mascara) |
| Kind errado em catálogo type `all` | `MediaItem+Preview` força `.movie` quando o type do catálogo não é um `Kind` válido |

---

## Decisões de produto (fechadas em 2026-07-11)

1. **Aba de canal = Home completa por serviço**, reutilizando `HomeView` com a tag do addon: hero + Top 10 FlixPatrol + acervo `streaming.<code>`.
2. **Roteamento híbrido mantido**: só FILME de serviço assinado (`isSubscribed`, hardcoded por ora) abre o app externo via deep link; séries e serviços não assinados vão SEMPRE via Infuse.
3. **Séries — Play inteligente**: o botão Reproduzir toca o próximo episódio não assistido (ou T1E1); abaixo, seção de episódios com seletor de temporada e cards com thumbnail/título/sinopse/progresso.
4. **Entrega fase a fase**: cada fase compila e é validada pelo dono do projeto (ele roda builds/testes) antes da próxima.

---

## Convenções obrigatórias

- **Concorrência**: o projeto usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Todo tipo novo de dados/parsing (DTOs, enums, lógica pura) deve ser `nonisolated` e `Sendable`. Os testes não herdam o default.
- **UI**: controles compactos que ciclam (padrão Dub/Leg/Best — um botão, labels curtos); cards de foco com lockup nativo (`Button(.borderless)` + `hoverEffect(.highlight)` no composite + `scrollClipDisabled`) — nunca `.card` nem vidro custom.
- **IDs de episódio**: usar `video.id` do meta **verbatim** no endpoint de streams. Nunca construir `contentId:S:E` na mão (anime mistura `tt…:0:E` e `kitsu:ID:EP` na mesma série).
- **Testes**: Swift Testing (`@Test`) em `StreamHubTests/`, fixtures JSON inline, sem rede.
- **Arquivos novos** precisam ser adicionados ao target correto no `project.pbxproj`.

---

## Fatos verificados ao vivo (2026-07-11)

- `manifest.json?tag=netflix` → 10 catálogos: `flixpatrol.netflix.br.movie/.series` + `streaming.nfx` (movie e series) + 6 núcleo (`search.*`, `gemini.search`, `calendar-videos` — todos com extra obrigatório).
- Tags de serviço: `netflix, disney, hbo, prime, paramount, hulu, apple, discovery, crunchyroll, claro, globo`. Divergências de nome: `.appleTV → "apple"`, `.globoplay → "globo"`.
- `/meta/series/tt0903747.json` → 80 `videos[]` com ids `tt0903747:S:E`; season 0 (especiais) vem PRIMEIRO no array.
- `/meta/series/mal:5114.json` → ids MISTOS na mesma série: especiais `tt1355642:0:E`, regulares `kitsu:3936:EP` (kitsu sem componente de season).
- FlixPatrol: 10 itens, sem extras (não pagina). `streaming.*`: 50/página, extras `genre` + `skip`.

Referências de contrato: [../api/metadata/03-filters-and-extras.md](../api/metadata/03-filters-and-extras.md), [../api/metadata/05-catalog-reference.md](../api/metadata/05-catalog-reference.md), [../api/metadata/06-id-system.md](../api/metadata/06-id-system.md), [../api/streams/id-formats.md](../api/streams/id-formats.md), [../api/streams/stream.md](../api/streams/stream.md).

---

## Ordem unificada de fases

A ordem entrega valor primeiro (abas navegáveis com filmes tocando) e resolve o ponto de contenção real — o contrato de roteamento no `PlaybackCoordinator` — uma única vez, na F2. A F4 pode andar em paralelo a F2/F3.

| Fase | Workstream | Escopo | Depende de |
|---|---|---|---|
| **F1** | A | `HomeConfiguration` + mapeamento MenuSection→tag/service/hero; filtro por config; títulos PT-BR; correção Kind type `all`; heroes de Séries/Animes corrigidos; top-up do hero | — |
| **F2** | A (+prep B) | Carimbo de serviço (rows + hero pool); `route(for:)` na forma final (decisão 2); guard de `play()` endurecido contra séries; extração `RuntimeParser` | F1 |
| **F3** | A | Ligar as 11 abas + verificação visual/polimento | F2 |
| **F4** | B | `MetaModels` + `MetadataAPI.meta(type:id:)` + `MetaProvider` | — (paralelo a F2/F3) |
| **F5** | B | `EpisodeItem`/`SeasonGroup`/`EpisodePlanner` + `SeriesDetailViewModel` | F2 (`RuntimeParser`), F4 |
| **F6** | B | `ResumeEntry` v2 + snapshot de sessão + watched store + avanço automático do card | F5 |
| **F7** | B | Play de episódio no `PlaybackCoordinator` (`streamRequest`, filename SxxExx, erro `.noEpisodes`) | F2, F6 |
| **F8** | B | UI de episódios na `MediaWindowView` (shelf + seletor de temporada + Play inteligente); reverte o guard temporário da F2 | F7 |
| **F9** | B | Continue Watching multi-kind (liga a flag nos presets series/animes; filmes já nasce ligado) | F8 |
| **F10** | A (opcional) | Fileiras por gênero (`genre` com percent-encoding) | F3 |

### Critérios de pronto por fase

- **F1**: suíte de testes nova passa (mapeamento completo dos 11 canais, filtragem com fixtures, Kind fallback, títulos, estilo top10); abas principais idênticas visualmente, exceto heroes de Séries/Animes corrigidos; canais AINDA em ComingSoon (gate explícito).
- **F2**: matriz de rota testada (filme assinado → externo; série assinada → Infuse; não-assinado → Infuse); série nunca chega ao fetch de streams; zero regressão em filmes/anime.
- **F3**: as 11 abas renderizam hero (7 itens com arte), Top 10 sem paginação, fileiras de acervo paginando, títulos PT-BR, badge no hero; play de filme roteia conforme decisão 2. Validação visual pelo dono do projeto.
- **F4**: fixtures de meta (tt e mal/kitsu mistos) parseiam; `metaRequest` correto para série/anime/filme; cache com TTL e dedupe.
- **F5**: `EpisodePlanner` passa em todos os cenários (agrupamento, especiais no fim, next-unwatched 4 passos, `episodeAfter` canônico, labels).
- **F6**: JSON v1 existente decodifica sem migração; callbacks de episódio atualizam/avançam/removem a entrada corretamente; watched store por perfil com cap.
- **F7**: episódio real toca via Infuse com filename `Título SxxExx.ext`; resume por videoId; verificação ao vivo de `/stream/series/tt…:0:E` no perfil anime documentada.
- **F8**: navegação por controle remoto completa (detalhe → episódios → play → volta); Play inteligente com label correto; convenções de foco respeitadas.
- **F9**: card de série no Continue Watching com `T2E5 · Restam N min`, abre o detalhe, retoma o episódio certo; card avança sozinho ao completar episódio.

---

## Escopo explicitamente fora deste roadmap

- Modo **Enhanced** (remux ffmpeg) — já especificado em [../enhanced/README.md](../enhanced/README.md); a F7 mantém o comportamento atual (`Best` → `.enhancedUnavailable`).
- `isSubscribed` configurável por perfil (fica hardcoded; decisão 2).
- Busca (`search.*`, `gemini.search`), calendário de episódios (`calendar-videos`) e notificações.
- Deep link para título específico em app externo (`titleDeepLink` permanece stub).
