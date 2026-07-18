# Workstream A — Abas de Canais como Homes por Serviço

Fases **F1–F3** (+ **F10** opcional) do [roadmap](./README.md). Objetivo: as 11 abas de "Canais" da sidebar renderizam Homes completas por serviço, reutilizando `HomeView`/`HomeViewModel`, com roteamento de playback conforme a decisão de produto 2.

---

## 1. Mapeamento MenuSection → tag → StreamingService → hero

**Onde mora:** novo arquivo `StreamHub/Navigation/MenuSection+Home.swift` com extensão de `MenuSection`. Mantém `MenuSection.swift` puramente presentacional e concentra o conhecimento do addon num único ponto — não criar um terceiro enum paralelo.

| MenuSection | tag do addon | StreamingService | heroCatalogId |
|---|---|---|---|
| `.netflix` | `netflix` | `.netflix` (nfx) | `flixpatrol.netflix.br.movie` |
| `.hbo` | `hbo` | `.hboMax` (hbm) | `flixpatrol.hbo-max.br.movie` |
| `.disney` | `disney` | `.disneyPlus` (dnp) | `flixpatrol.disney.br.movie` |
| `.appleTV` | `apple` | `.appleTVPlus` (atp) | `flixpatrol.apple-tv.br.movie` |
| `.prime` | `prime` | `.primeVideo` (amp) | `flixpatrol.amazon-prime.br.movie` |
| `.crunchyroll` | `crunchyroll` | `.crunchyroll` (cru) | `mal.season_top` |
| `.claro` | `claro` | `.claroVideo` (clv) | `flixpatrol.apple-tv-store.br.movie` |
| `.paramount` | `paramount` | `.paramountPlus` (pmp) | `flixpatrol.paramount.br.movie` |
| `.globoplay` | `globo` | `.globoplay` (gop) | `flixpatrol.globoplay.br.movie` |
| `.discovery` | `discovery` | `.discoveryPlus` (dpe) | `flixpatrol.discovery-plus.us.all` |
| `.hulu` | `hulu` | `.hulu` (hlu) | `flixpatrol.hulu.us.movie` |

> ⚠️ As tags NÃO derivam do rawValue do `MenuSection`: `.appleTV → "apple"`, `.globoplay → "globo"`. Mapeamento explícito obrigatório, sem derivação por string.

**Tipo de configuração** — novo `StreamHub/Catalog/HomeConfiguration.swift`, substituindo o par solto `(tag, heroCatalogId)`:

```swift
nonisolated struct HomeConfiguration: Hashable, Sendable {
    let tag: String                      // "movie" | "series" | "anime" | "netflix" | ...
    let heroCatalogId: String
    let service: StreamingService?      // nil para filmes/series/animes
    let showsContinueWatching: Bool     // ver §5
    var isServiceHome: Bool { service != nil }
    func includes(_ def: CatalogDefinition) -> Bool
    func rowTitle(for def: CatalogDefinition) -> String

    static let filmes: HomeConfiguration   // tag "movie",  hero "mdblist.2236",        CW true
    static let series: HomeConfiguration   // tag "series", hero "trakt.trending.shows", CW false (true na F9)
    static let animes: HomeConfiguration   // tag "anime",  hero "mal.season_top",       CW false (true na F9)
}

extension MenuSection {
    var homeConfiguration: HomeConfiguration?   // nil só para .search
}
```

`RootView.destination(for:)` passa a resolver via `homeConfiguration`. **Gate da F1**: na F1, apenas `MenuSection.principais` usam a config; os canais continuam retornando `ComingSoonView` até a F3 (a config deles já existe e é testada, só não é ligada à navegação).

---

## 2. Filtragem de catálogos por config

O filtro atual (`HomeViewModel.swift:30` — `$0.type == tag && !$0.hasRequiredExtra`) não funciona para tags de serviço (types mistos `movie`/`series`/`all`/`anime`). Nova estratégia, encapsulada em `HomeConfiguration.includes(_:)`:

- **Home de tipo** (filmes/series/animes): comportamento atual — `def.type == tag && !def.hasRequiredExtra`.
- **Home de serviço**: `!def.hasRequiredExtra && !isCoreCatalog(def)`, onde `isCoreCatalog` = id com prefixo `search.` ou `gemini.` ou id `calendar-videos`.

Os 6 catálogos núcleo têm todos extra obrigatório, então `!hasRequiredExtra` já os exclui hoje — a denylist por id é cinto-e-suspensório caso o addon mude flags. **Não** usar allowlist por prefixo (`flixpatrol.*`/`streaming.*`): quebraria o `mal.season_top` da Crunchyroll e qualquer catálogo que o addon adicione à tag no futuro.

**Ordenação das fileiras**: manter a ordem do manifest (zero código). Verificado: em toda tag de serviço, o(s) catálogo(s) de destaque (FlixPatrol / `mal.season_top`) vêm antes do acervo `streaming.*` — Top 10 primeiro naturalmente. (globo/claro/discovery têm um único destaque; crunchyroll usa `mal.season_top` no lugar de FlixPatrol.)

**Títulos das fileiras (PT-BR)** — `rowTitle(for:)`, apenas em homes de serviço (homes de tipo continuam com `def.name`):

| Catálogo | Título |
|---|---|
| `flixpatrol.*` type `movie` | "Top 10: Filmes" |
| `flixpatrol.*` type `series` | "Top 10: Séries" |
| `flixpatrol.*` type `all` | "Top 10" |
| `streaming.*` type `movie` | "Filmes" |
| `streaming.*` type `series` | "Séries" |
| `mal.season_top` | "Top da temporada" |

**Assinaturas alteradas:**
- `HomeViewModel.init(config: HomeConfiguration, api: MetadataAPI = MetadataAPI())`
- `HomeView.init(config: HomeConfiguration)`
- `HomeViewModel.style(for def: CatalogDefinition) -> MediaRow.Style` — top10 se `def.id.hasPrefix("flixpatrol.")` OU nome começa com "Top 10" (o teste por id é o principal: nomes serão renomeados para PT-BR e catálogos flixpatrol não têm `skip` — não podem paginar).

---

## 3. Hero por serviço (com top-up)

Heroes da tabela do §1. Top 10 de filmes é o conteúdo mais atual/reconhecível e filmes têm melhor cobertura de backdrop+logo. Casos especiais já resolvidos na tabela: discovery usa o único ranking (`…us.all`), globo/claro usam o único flixpatrol movie que têm, crunchyroll usa `mal.season_top`.

> ⚠️ **Top-up obrigatório (correção da revisão):** o fallback atual (`HomeViewModel.swift:37`) só dispara quando o id do hero está AUSENTE das pages — se o flixpatrol existir mas render menos de 7 itens com backdrop+logo, o hero fica magro ou vazio, sem fallback. Implementar top-up: completar o pool até 7 com itens com arte das demais fileiras (na ordem do manifest), deduplicando por `contentId`.

Não usar `streaming.<code>` como heroCatalogId (id duplicado em movie+series — match do hero é por `def.id` apenas).

---

## 4. Casos especiais

### 4.1 Discovery type `all` — bug de Kind

A rota de catálogo funciona (`CatalogRow` chama `api.catalog(type: "all", id: …)` normalmente). O bug está em `MediaItem+Preview.swift:27`: `Kind(rawValue: catalogType ?? preview.type) ?? .movie` — com `catalogType = "all"`, TODO item vira `.movie`, inclusive séries (que passariam no guard de play e tentariam `/stream/movie/tt…`). Correção:

```swift
kind: Kind(rawValue: catalogType ?? "") ?? Kind(rawValue: preview.type) ?? .movie
```

Prefere o type do catálogo quando é um `Kind` válido (preserva o comportamento `anime` dos catálogos MAL) e cai para o `type` do item quando não é (caso `all`).

### 4.2 Crunchyroll

`mal.season_top` tem `def.type == "anime"` → kind `.anime` → `isAnime` → perfil anime no playback (caminho existente). Itens de `streaming.cru` ficam `isAnime == true` por `streamingSource == .crunchyroll` (`MediaItem.swift:112`) e/ou ids `mal:`/`kitsu:`. `mal.season_top` pagina normalmente (25/pág, tem `skip`) como fileira `.standard`.

### 4.3 Heroes inválidos das abas principais

- Séries: `"tmdb.trending_series"` → **`trakt.trending.shows`** (primeiro catálogo de séries do manifest, semanticamente "em alta").
- Animes: `"mal.season_top_anime"` → **`mal.season_top`** (destaque atual; `mal.top_anime` é ranking histórico, menos vitrine).

Hoje o bug é mascarado pelo fallback (hero vira merge de todas as fileiras) — a correção muda o hero visível, intencionalmente.

---

## 5. Continue Watching nas abas de serviço

**Não exibir neste workstream.** Filmes de serviço assinado abrem no app externo (sem callback de posição → nunca geram `ResumeEntry`) e séries ainda não tocam — a fileira ficaria vazia/enganosa. Trocar o teste hardcoded `tag == "movie"` (`HomeView.swift:56`) por `config.showsContinueWatching`; na F9 os presets de séries/animes ligam a flag. Reavaliar CW por serviço no futuro com filtro `entries.filter { $0.serviceCode == config.service?.rawValue }` (o campo já existe).

---

## 6. Carimbo de serviço + roteamento (F2)

**Gap:** `streamingSource` é derivado só de `catalogId` com prefixo `streaming.` — itens das fileiras `flixpatrol.*` (e `mal.season_top` na aba Crunchyroll) ficariam com `streamingSource == nil` (Top 10 da Netflix rotearia para Infuse e sem badge). Correção: carimbar o serviço do CONTEXTO da aba, propagando `HomeConfiguration.service`:

- `CatalogRow.init(api:type:id:title:style:firstPage:service:)` — novo parâmetro `service: StreamingService? = nil`, usado no init e em `fetchNextPage()`.
- `MediaItem.init(preview:catalogType:catalogId:service:)` — `streamingSource = service ?? catalogId.flatMap(StreamingService.init(catalogId:))`.
- **Hero pool também** (correção da revisão): `HomeViewModel` constrói `heroItems` com `MediaItem(preview:)` cru — sem o carimbo, o badge de serviço no hero nunca renderiza e um futuro Play do hero rotearia errado. Construir o pool com a def de origem (`catalogType`/`catalogId`/`service`).

O carimbo pelo contexto (e não por parse do slug flixpatrol) é autoritativo: cobre `mal.season_top` (badge Crunchyroll) e o caso Claro (`flixpatrol.apple-tv-store.br.movie` carimbado como Claro Video — semântica da aba).

**Roteamento final** (decisão 2 — forma DEFINITIVA, feita UMA vez aqui; a F7 não toca mais em `route`):

```swift
func route(for item: MediaItem) -> Route {
    if item.kind == .movie, let service = item.streamingSource, service.isSubscribed {
        return .externalService(service)
    }
    return .infuse
}
```

Matriz resultante: filme assinado → app externo; filme não-assinado → Infuse; **série (assinada ou não) → Infuse**; anime → Infuse.

**Guard de `play()` endurecido (temporário até F8):** séries de `streaming.cru` já ficam `isAnime == true` pela derivação existente (`streamingSource == .crunchyroll` em `MediaItem.swift:112` / ids `mal:`·`kitsu:`); ao ligar a aba Crunchyroll na F3, elas passam no guard atual e chamariam `/stream/anime/tt…` SEM episódio — e o addon NÃO retorna vazio para id incompleto: retorna streams genéricos do cache do debrid ([../api/streams/id-formats.md](../api/streams/id-formats.md) §5), tocando vídeo ERRADO. Correção de 1 linha: bloquear `kind == .series` mesmo com `isAnime` (`guard state != .loading, item.kind == .movie || (item.isAnime && item.kind != .series) else { return }`). A F8 reverte ao introduzir o caminho de episódio.

**Extração `RuntimeParser`** (prep do workstream B, feita aqui para tocar o coordinator uma vez só): mover `runtimeMinutes(from:)` do `PlaybackCoordinator` para `nonisolated enum RuntimeParser` compartilhado.

---

## 7. Riscos e pegadinhas

1. **FlixPatrol não pagina** (sem extra `skip`): detecção top10 por `id.hasPrefix("flixpatrol.")` garante `style == .top10` (que já não pagina e capa em 10), independente do nome renomeado.
2. **Duplicados Top 10 × acervo**: não deduplicar — `MediaItem.id` é UUID (sem colisão de ForEach) e duplicação é o padrão de mercado; dedupe quebraria os ranks.
3. **Badges**: `serviceBadge` só renderiza no hero e no card de Continue Watching — carimbar serviço não polui as fileiras. Badge no hero da própria aba é redundante mas sinaliza o roteamento; manter.
4. **Abas com poucas fileiras**: netflix/disney/hbo/prime/paramount/hulu/apple = 4 fileiras; globo/claro/discovery/crunchyroll = 3. Aceitável no MVP; enriquecimento na F10.
5. **Copy do estado de falha**: `HomeView.failureView` diz "Não foi possível carregar os filmes." — generalizar para "Não foi possível carregar o conteúdo.".
6. **`mal.season_top` compartilhado** entre abas Animes e Crunchyroll: instâncias de `CatalogRow` independentes, sem estado compartilhado — sem risco.

---

## 8. Fases e arquivos

### F1 — Fundações (sem mudança visível nos canais)

| Arquivo | Ação |
|---|---|
| `StreamHub/Catalog/HomeConfiguration.swift` | **criar** — struct + presets `filmes/series/animes` (§1, §2) |
| `StreamHub/Navigation/MenuSection+Home.swift` | **criar** — `var homeConfiguration` com a tabela do §1 |
| `StreamHub/Catalog/MediaItem+Preview.swift` | **modificar** — fallback de Kind (§4.1) |
| `StreamHub/Navigation/RootView.swift` | **modificar** — destino via `homeConfiguration` para `principais`; heroes de Séries/Animes corrigidos (§4.3); canais seguem em ComingSoon |
| `StreamHub/Features/Home/HomeView.swift` | **modificar** — `init(config:)`, `showsContinueWatching`, copy de falha |
| `StreamHub/Catalog/HomeViewModel.swift` | **modificar** — `init(config:api:)`, filtro via `config.includes`, `style(for def:)`, títulos via `rowTitle`, hero + top-up (§3) |

### F2 — Carimbo de serviço + roteamento

| Arquivo | Ação |
|---|---|
| `StreamHub/Catalog/CatalogRow.swift` | **modificar** — parâmetro `service:`, propagar em `fetchNextPage()` |
| `StreamHub/Catalog/MediaItem+Preview.swift` | **modificar** — parâmetro `service:` (§6) |
| `StreamHub/Catalog/HomeViewModel.swift` | **modificar** — passar `config.service` às rows e ao hero pool |
| `StreamHub/Playback/PlaybackCoordinator.swift` | **modificar** — `route(for:)` final; guard endurecido; extração `RuntimeParser` |
| `StreamHub/Playback/RuntimeParser.swift` | **criar** — `nonisolated enum RuntimeParser` |

### F3 — Ligar as 11 abas

| Arquivo | Ação |
|---|---|
| `StreamHub/Navigation/RootView.swift` | **modificar** — canais renderizam `HomeView(config:)`; ComingSoon só para `.search` |

Verificação visual por aba (dono do projeto roda): hero com 7 itens, Top 10 sem paginação, títulos PT-BR, badge no hero, rota de playback conforme decisão 2.

### F10 (opcional) — Fileiras por gênero

| Arquivo | Ação |
|---|---|
| `StreamHub/Catalog/MetadataAPI.swift` | **modificar** — `catalog(type:id:genre: String? = nil, skip: Int = 0)` montando `/catalog/{type}/{id}/genre={G}&skip={N}.json`; **percent-encoding explícito** do valor de `genre` (opções PT-BR têm acento/espaço; usar o valor EXATO de `extra.options`, case-sensitive) |
| `StreamHub/Catalog/HomeViewModel.swift` + `CatalogRow.swift` | **modificar** — fileiras extras curadas de `streaming.<code>` com `genre` fixo |

---

## 9. Plano de testes (Swift Testing, sem rede)

Novo `StreamHubTests/HomeConfigurationTests.swift` + ampliações em `StreamHubTests.swift`, seguindo o padrão de JSON inline existente.

**F1:**
- Mapeamento completo: iterar `MenuSection.canais` — todo canal tem config não-nil com tag/service/hero da tabela §1 (asserts explícitos para `.appleTV → "apple"` e `.globoplay → "globo"`); `.search` → nil; presets `filmes/series/animes` com heroes `mdblist.2236` / `trakt.trending.shows` / `mal.season_top`.
- Filtragem com fixture de manifest da tag netflix (6 núcleo com `isRequired` + 4 do serviço): `includes` mantém exatamente os 4 na ordem do manifest; variantes discovery (type `all`), crunchyroll (`mal.season_top` incluído) e núcleo SEM `isRequired` (denylist segura a exclusão).
- Kind fallback: `catalogType: "all"` + `preview.type == "series"` → `.series`; `"movie"` → `.movie`; `catalogType: "anime"` → `.anime` (regressão).
- `rowTitle(for:)`: os 6 casos da tabela §2 + home de tipo → `def.name`.
- Estilo: id `flixpatrol.*` com nome PT-BR → `.top10`; `mal.season_top` → `.standard`.
- Top-up do hero: pool com hero de 2 itens com arte + fileiras extras → completa até 7 sem duplicar `contentId`.

**F2:**
- Carimbo: `service: .netflix` + catalogId flixpatrol → `streamingSource == .netflix`; sem `service`, catalogId `streaming.hbm` → `.hboMax` (regressão); `service` vence catalogId.
- `isAnime` de item carimbado `.crunchyroll` com kind `.series` → true.
- Rota (`@MainActor @Test`): filme assinado → `.externalService`; **série assinada → `.infuse`**; filme não-assinado → `.infuse`; anime → `.infuse`.
- Guard: `play()` com série `isAnime == true` não muda o estado.
- `RuntimeParser`: paridade com o comportamento atual ("2h 3min", "45min", inválido → nil).

**F3:** sem testes novos (ligação de UI); rodar a suíte completa para regressão.

**F10:** montagem de path com `genre` percent-encoded (extrair builder de path puro testável).
