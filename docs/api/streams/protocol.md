# Protocolo de Addon do Stremio

> Base conceitual para entender todas as rotas desta API. Resume o **Stremio Addon Protocol** (fonte oficial: [`Stremio/stremio-addon-sdk`](https://github.com/Stremio/stremio-addon-sdk), `docs/protocol.md` + `docs/api/`) e destaca o que **esta instância AIOStreams** realmente implementa.

---

## 1. Modelo mental

Um addon Stremio é **apenas um servidor HTTP** que:

1. Serve um `/manifest.json` declarando o que sabe fazer (recursos, tipos, prefixos de ID).
2. Responde a requisições de recurso no formato `/{resource}/{type}/{id}.json` retornando JSON.

Não há autenticação por header no protocolo: a configuração do usuário viaja **embutida na URL** (ver [README — token CONFIG](./README.md#o-token-config)). Tudo é `GET`, tudo é JSON, tudo é stateless.

Recursos definidos pelo protocolo: `catalog`, `meta`, `stream`, `subtitles`, `addon_catalog`.
Esta instância implementa: **`catalog`, `meta`, `stream`** (não há `subtitles` nem `addon_catalog`).

---

## 2. Formato das rotas

`{BASE}` = URL base (host + prefixo + uuid + token), ver [README §2](./README.md#2-anatomia-da-url-base).

| Recurso | Rota | Implementado aqui |
|---|---|:--:|
| manifest | `/manifest.json` | ✅ |
| catalog | `/catalog/{type}/{id}.json` | ✅ |
| catalog (com extra) | `/catalog/{type}/{id}/{extra}.json` | ✅ |
| meta | `/meta/{type}/{id}.json` | ✅ |
| stream | `/stream/{type}/{id}.json` | ✅ |
| subtitles | `/subtitles/{type}/{id}.json` | ❌ |
| addon_catalog | `/addon_catalog/{type}/{id}.json` | ❌ |

Regras:

- O **sufixo `.json` é obrigatório** em toda rota de recurso.
- `{type}` é um *content type* (`movie`, `series`, `tv`, … — ver [§5](#5-content-types)).
- `{id}` é o identificador do conteúdo (ver [id-formats.md](./id-formats.md)).
- `{id}` pode **conter `:`** (ex.: séries `tt0903747:1:1`). O `:` aparece **literal** na URL — é caractere válido em segmento de path (RFC 3986); não precisa ser percent-encoded. *(O protocolo não exige encoding explícito do `:`.)*

---

## 3. Extra args (paginação, busca, filtro)

Quando um recurso aceita parâmetros extras, eles entram como **um segmento de path adicional**, antes do `.json`, no formato **query string**:

```
/catalog/{type}/{id}/{chave1=valor1&chave2=valor2}.json
```

Exemplo (paginação do catálogo desta instância):

```
/catalog/other/2fe791b.torrentio-torbox-torrents/skip=100.json
```

Detalhes (confirmados no roteador oficial `src/getRouter.js`):

- O SDK lê o **último segmento da URL crua**, remove `.json` e aplica `querystring.parse`.
- **Os valores devem ser percent-encoded**; um `&` literal dentro de um valor vira `%26` (senão quebra a separação de parâmetros). Espaço vira `%20`.
  - Ex.: `genre=Action %26 Adventure` → `…/genre=Action%20%26%20Adventure.json` → parseado como `{ genre: "Action & Adventure" }`.
- Extra params padronizados pelo protocolo: `search`, `genre`, `skip`. **Esta instância expõe apenas `skip`** nos catálogos (ver [manifest.md](./manifest.md) e [catalog.md](./catalog.md)).

### Paginação por `skip`

- `skip` = número de itens já consumidos desde o início.
- O tamanho de página padrão do Stremio é **100**. Logo, `skip` costuma ser múltiplo de 100.
- **Fim do catálogo:** se uma resposta traz **menos de 100 itens**, o cliente assume que acabou (não há próxima página).

---

## 4. Respostas e envelopes JSON

Cada recurso devolve um envelope com uma chave fixa:

| Recurso | Envelope | Tipo do payload |
|---|---|---|
| manifest | *(objeto raiz)* | objeto Manifest |
| catalog | `{ "metas": [ … ] }` | array de **Meta Preview** |
| meta | `{ "meta": { … } }` | objeto **Meta** (único) |
| stream | `{ "streams": [ … ] }` | array de **Stream** |
| subtitles | `{ "subtitles": [ … ] }` | array de **Subtitle** |

Objetos detalhados: [manifest.md](./manifest.md), [stream.md](./stream.md), [meta.md](./meta.md), [catalog.md](./catalog.md).

A lista de `streams` deve vir **ordenada da maior para a menor relevância/qualidade** (responsabilidade do addon). Nesta instância, segundo a descrição do addon, a config prioriza dublado/PT-BR — a ordem observada tende a refletir isso.

---

## 5. Content types

Padrão do protocolo: `movie`, `series`, `channel`, `tv`.
Esta instância **estende** com tipos próprios do AIOStreams:

| Tipo | Origem | Uso aqui |
|---|---|---|
| `movie` | padrão | Filmes (ID IMDb/TMDB…) |
| `series` | padrão | Séries (`id:season:episode`) |
| `tv` | padrão | Canais ao vivo |
| `anime` | extensão AIOStreams | Animes (IDs Kitsu/MAL/AniList…) |
| `events` | extensão AIOStreams | Eventos/transmissões |
| `other` | extensão AIOStreams | Itens de catálogo da biblioteca debrid |

> `channel` não é usado por esta instância.

---

## 6. Headers de cache e CORS

- **CORS:** toda rota (inclusive `/manifest.json`) responde `Access-Control-Allow-Origin: *`.
- **Cache:** o protocolo permite ao addon devolver `cacheMaxAge`, `staleRevalidate`, `staleError`, que o servidor converte em `Cache-Control: max-age=…, stale-while-revalidate=…, stale-if-error=…, public`. Nesta instância, observa-se `ETag` fraco no manifest (use `If-None-Match` para obter `304`).
- **Redirect:** um handler pode responder `{ redirect: <url> }` → HTTP **307**. (Distinto do `302` que a `stream.url` emite ao resolver o arquivo no CDN — ver [stream.md](./stream.md#6-comportamento-da-url).)

---

## 7. Diferenças entre o protocolo e esta instância

| Aspecto | Protocolo padrão | Esta instância (AIOStreams) |
|---|---|---|
| Recursos | catalog, meta, stream, subtitles, addon_catalog | catalog, meta, stream |
| Tipos | movie, series, channel, tv | + anime, events, other (sem channel) |
| Extra de catálogo | search, genre, skip | apenas skip |
| Config | "user data" JSON opcional na URL | **token AES obrigatório** na URL |
| Rate limit | não especificado | **5 req / 5 s** |

---

## 8. Fontes oficiais

- Protocolo: `github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md`
- Respostas: `docs/api/responses/{manifest,stream,meta,subtitles,content.types}.md`
- Requests/handlers: `docs/api/requests/define{Catalog,Meta,Stream,Subtitles}Handler.md`
- Roteamento/encoding (autoritativo): `src/getRouter.js`
- AIOStreams: `github.com/Viren070/AIOStreams`
