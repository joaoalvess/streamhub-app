# Formatos de ID

> Como montar o `{id}` das rotas `/stream`, `/meta` e `/catalog`. Os prefixos aceitos são declarados no [manifest](./manifest.md) (`idPrefixes` por recurso).

---

## 1. Regra geral

O `{id}` na URL identifica o conteúdo por um **catálogo externo** (IMDb, TMDB, Kitsu…). O prefixo do ID diz a que catálogo ele pertence e **decide se esta API será chamada** (o Stremio só roteia para o addon IDs cujo prefixo está em `idPrefixes`).

- **Filme:** `{idExterno}` (ex.: `tt0111161`).
- **Série:** `{idExterno}:{temporada}:{episódio}` (ex.: `tt0903747:1:1`). O `:` vai **literal** na URL.
- **Anime:** `{idExterno}:{episódio}` (ex.: `kitsu:1376:1`).

---

## 2. Prefixos aceitos pelo recurso `stream`

Declarados em `manifest.resources[stream].idPrefixes`. Agrupados por catálogo:

| Prefixo(s) | Catálogo | Tipo(s) típico(s) | Exemplo de `{id}` |
|---|---|---|---|
| `tt`, `imdb` | **IMDb** | movie, series | `tt0111161`, `tt0903747:1:1` |
| `tmdb`, `tmdb:` | **TMDB** (The Movie Database) | movie, series | `tmdb:278` |
| `tvdb`, `tvdb:` | **TheTVDB** | series | `tvdb:81189` |
| `kitsu`, `kitsu:` | **Kitsu** | anime | `kitsu:1376:1` |
| `mal`, `mal:` | **MyAnimeList** | anime | `mal:1535:1` |
| `anilist` | **AniList** | anime | `anilist:1535:1` |
| `anidb`, `anidb_id`, `anidbid` | **AniDB** | anime | `anidb:…` |
| `animeplanet`, `ap` | **Anime-Planet** | anime | `animeplanet:…` |
| `anisearch` | **aniSearch** | anime | `anisearch:…` |
| `notifymoe`, `nm` | **Notify.moe** | anime | `notifymoe:…` |
| `mf` | identificador interno **MediaFusion** | other/meta | ver [meta.md](./meta.md) |
| `dl` | identificador interno (downloads/biblioteca) | other/meta | ver [meta.md](./meta.md) |

> O manifest lista variantes com e sem `:` (ex.: `kitsu` e `kitsu:`) para casar tanto o prefixo simples quanto a forma com namespace.

---

## 3. Como montar por tipo

### Filme (`movie`)
```
/stream/movie/{idExterno}.json
```
```bash
curl -s "$BASE/stream/movie/tt0111161.json"        # Um Sonho de Liberdade (IMDb)
```

### Série (`series`)
Formato do ID: `{idExterno}:{temporada}:{episódio}` (numeração absoluta de temporada/episódio do catálogo externo).
```
/stream/series/{idExterno}:{S}:{E}.json
```
```bash
curl -s "$BASE/stream/series/tt0903747:1:1.json"   # Breaking Bad S01E01 (IMDb)
```

### Anime (`anime`)
Formato do ID: `{catálogo}:{idAnime}:{episódio}`.
```
/stream/anime/{catálogo}:{idAnime}:{E}.json
```
```bash
curl -s "$BASE/stream/anime/kitsu:1376:1.json"     # Death Note ep.1 (Kitsu)
```

### TV / Events
`tv` e `events` usam IDs próprios das fontes ao vivo. Não há ID externo padronizado; obtenha o `{id}` a partir do catálogo/meta correspondente.

---

## 4. Resolução de qual ID usar

O StreamHub normalmente parte de um **IMDb ID** (`tt…`) vindo do TMDB/Cinemeta:

- Para **movie/series**, prefira `tt…` — é o caminho mais coberto pelos scrapers.
- Para **anime**, IDs IMDb funcionam mal; use **Kitsu** (`kitsu:…`) ou **MAL** (`mal:…`). É preciso mapear o título → ID Kitsu/MAL antes de chamar.
- Conversões entre catálogos (IMDb ↔ TMDB ↔ Kitsu) são responsabilidade do cliente; esta API **não** expõe endpoint de conversão.

---

## 5. Comportamento com ID inválido/desconhecido

⚠️ Importante: um ID inexistente **não** retorna `404` nem `{ streams: [] }`. Observado: `GET /stream/movie/tt0000000.json` devolveu **streams genéricos** (10 no teste; itens do cache do debrid) em vez de erro. Ou seja:

- **Não** confie em "lista vazia = ID inválido".
- Sempre **valide** se os streams retornados correspondem ao título esperado (cruzar `behaviorHints.filename`/`description` com o título/ano alvo). Ver [stream.md](./stream.md) e [integration.md](./integration.md).
