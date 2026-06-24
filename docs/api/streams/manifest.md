# Rota: `/manifest.json`

> Documento de capacidades do addon. **Primeira chamada** que o StreamHub deve fazer: declara quais recursos, tipos e prefixos de ID a API suporta. Conteúdo estático (varia só quando a config muda).

```
GET {BASE}/manifest.json
Content-Type: application/json; charset=utf-8
```

```bash
curl -s "$BASE/manifest.json" | jq .
```

---

## 1. Resposta real (verbatim)

```json
{
  "name": "AIOStream",
  "id": "com.aiostreams.viren070.8b977f8f-511",
  "version": "2.30.3",
  "description": "AIOStreams configurado para priorizar conteudo dublado em PT-BR.",
  "catalogs": [
    { "type": "other", "id": "2fe791b.torrentio-torbox-torrents", "name": "TorBox Torrents", "extra": [ { "name": "skip" } ] },
    { "type": "other", "id": "2fe791b.torrentio-torbox-usenet",   "name": "TorBox Usenet",   "extra": [ { "name": "skip" } ] },
    { "type": "other", "id": "2fe791b.torrentio-torbox-webdl",    "name": "TorBox WebDL",    "extra": [ { "name": "skip" } ] }
  ],
  "resources": [
    {
      "name": "stream",
      "types": ["movie", "series", "anime", "tv", "events"],
      "idPrefixes": ["tt","imdb","mal","tvdb","tmdb","kitsu","anilist","anidb","anidb_id","anidbid","animeplanet","ap","anisearch","notifymoe","nm","kitsu:","mal:","tmdb:","tvdb:","mf","dl"]
    },
    {
      "name": "meta",
      "types": ["other", "movie", "series", "tv", "events"],
      "idPrefixes": ["torbox","mf","dl","aiostreamserror"]
    },
    { "name": "catalog", "types": ["other"] }
  ],
  "types": ["movie", "series", "anime", "tv", "events", "other"],
  "logo": "https://raw.githubusercontent.com/Viren070/AIOStreams/refs/heads/main/packages/frontend/public/logo.png",
  "behaviorHints": { "configurable": true, "configurationRequired": false },
  "addonCatalogs": []
}
```

---

## 2. Campos de topo

| Campo | Valor | Significado |
|---|---|---|
| `name` | `AIOStream` | Nome exibido. (O projeto é "AIOStreams"; esta instância usa `AIOStream` no name.) |
| `id` | `com.aiostreams.viren070.8b977f8f-511` | Identificador único do addon. Inclui um sufixo derivado do UUID da instância. |
| `version` | `2.30.3` | [SemVer](https://semver.org) do AIOStreams. |
| `description` | "AIOStreams configurado para priorizar conteudo dublado em PT-BR." *(sem acento no original)* | Texto livre do addon; sinaliza que a config prioriza **dublado/PT-BR** (tende a refletir na ordenação dos streams). |
| `types` | `["movie","series","anime","tv","events","other"]` | Todos os content types que aparecem em algum recurso. Ver [protocol §5](./protocol.md#5-content-types). |
| `logo` | URL do logo AIOStreams | Ícone do addon. |
| `behaviorHints` | `{configurable, configurationRequired}` | Ver [§5](#5-behaviorhints). |
| `addonCatalogs` | `[]` | Não atua como catálogo de outros addons. |
| `resources` | 3 objetos | Ver [§3](#3-resources). |
| `catalogs` | 3 objetos | Ver [§4](#4-catalogs). |

> Não há `contactEmail`, `background`, `idPrefixes` de topo nem `config` no manifest público (a config viaja no token da URL, não como `config[]` declarado).

---

## 3. `resources`

Forma longa (objeto `{name, types, idPrefixes}`). Define **quais rotas existem e para quais tipos/IDs**.

### `stream` — a rota central
- **types:** `movie`, `series`, `anime`, `tv`, `events`.
- **idPrefixes:** `tt`, `imdb`, `mal`, `tvdb`, `tmdb`, `kitsu`, `anilist`, `anidb`, `anidb_id`, `anidbid`, `animeplanet`, `ap`, `anisearch`, `notifymoe`, `nm`, `kitsu:`, `mal:`, `tmdb:`, `tvdb:`, `mf`, `dl`.
- Cobre IMDb/TMDB/TVDB (filmes e séries) e todos os catálogos de anime. Detalhes em [id-formats.md](./id-formats.md). Resposta em [stream.md](./stream.md).

### `meta`
- **types:** `other`, `movie`, `series`, `tv`, `events`.
- **idPrefixes:** `torbox`, `mf`, `dl`, `aiostreamserror`.
- Opera sobre itens da **biblioteca debrid** e mensagens de erro (`aiostreamserror`). Ver [meta.md](./meta.md).

### `catalog`
- **types:** `other`.
- Sem `idPrefixes` (catálogos são sempre requisitados pelos `id` declarados em `catalogs`). Ver [catalog.md](./catalog.md).

---

## 4. `catalogs`

Três catálogos, todos `type: "other"`, todos com paginação por `skip` (sem busca/gênero).

| `id` | `name` | extra |
|---|---|---|
| `2fe791b.torrentio-torbox-torrents` | TorBox Torrents | `skip` |
| `2fe791b.torrentio-torbox-usenet` | TorBox Usenet | `skip` |
| `2fe791b.torrentio-torbox-webdl` | TorBox WebDL | `skip` |

Representam as três frentes da biblioteca do TorBox: **Torrents**, **Usenet** e **WebDL** (downloads diretos). Uso e paginação em [catalog.md](./catalog.md).

---

## 5. `behaviorHints`

| Campo | Valor | Efeito |
|---|---|---|
| `configurable` | `true` | Existe página de configuração em `{BASE}/configure` (HTML). |
| `configurationRequired` | `false` | O addon **já está configurado** (token válido na URL); funciona imediatamente, sem passo de setup. |

---

## 6. Como o StreamHub usa o manifest

1. **Cache local:** buscar 1x e cachear (use `ETag`/`If-None-Match` para revalidar barato → `304`).
2. **Descoberta de capacidades:** antes de chamar `/stream/{type}/…`, confirmar que `type` está em `resources[stream].types` e que o prefixo do ID está em `resources[stream].idPrefixes` — evita requisições que o addon ignoraria.
3. **Catálogos:** popular menus de "biblioteca" a partir de `catalogs[]` (Torrents/Usenet/WebDL).
4. **Versão:** logar `version` para diagnóstico (o formato de resposta pode mudar entre versões do AIOStreams).
