# Rota: `/meta` — detalhes de um item da biblioteca

> Retorna metadados (poster, background, etc.) e **streams inline** de um item obtido via [`/catalog`](./catalog.md). Diferente de [`/stream`](./stream.md): `/meta` descreve algo que **já está na biblioteca do debrid**; `/stream` faz scraping de fontes para um título por ID externo.

```
GET {BASE}/meta/{type}/{id}.json
Content-Type: application/json; charset=utf-8
```

- `{type}` ∈ `other`, `movie`, `series`, `tv`, `events`.
- `{id}` com prefixo `torbox`, `mf`, `dl` ou `aiostreamserror` (ver [§4](#4-prefixos-de-id-de-meta)).

```bash
curl -s "$BASE/meta/other/torbox:torrents-44797938.json" | jq .
```

---

## 1. Resposta (verbatim, abreviada)

```json
{
  "meta": {
    "id": "torbox:torrents-44797938",
    "type": "other",
    "name": "Scary.Movie.2026.1080p.CAMRip.Dublado.V.3.mkv",
    "poster": "https://images.metahub.space/poster/medium/tt32093575/img",
    "background": "https://images.metahub.space/background/medium/tt32093575/img",
    "logo": "https://images.metahub.space/logo/medium/tt32093575/img",
    "videos": [
      {
        "id": "tt32093575",
        "title": "Scary.Movie.2026…/Scary.Movie.2026.1080p.CAMRip.Dublado.V.3.mkv",
        "released": "2026-06-24T06:01:08.000Z",
        "thumbnail": "https://images.metahub.space/background/small/tt32093575/img",
        "streams": [
          {
            "name": "Torrentio Unknown",
            "description": "",
            "url": "https://api.torbox.app/v1/api/torrents/requestdl?token=…&torrent_id=44797938&file_id=0&redirect=true",
            "behaviorHints": { "bingeGroup": "com.aiostreams.viren070|no service|false" },
            "streamData": {
              "type": "http", "proxied": false, "duration": 0, "library": false,
              "torrent": { "private": false, "freeleech": false },
              "addon": "Torrentio", "keywordMatched": false, "id": "2fe791b-0"
            }
          }
        ]
      }
    ],
    "infoHash": "255b52fc56509fd7091fd10448c82b0d196a0d65"
  }
}
```

---

## 2. Objeto `meta`

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | Mesmo `id` do catálogo (`torbox:torrents-…`). |
| `type` | string | `other`. |
| `name` | string | Nome do release/arquivo. |
| `poster` / `background` / `logo` | string (URL) | Artes via `images.metahub.space`, casadas com um **IMDb ID** (ex.: `tt32093575`) inferido do release. |
| `videos` | array | Arquivos reproduzíveis do item. Ver [§3](#3-objeto-video-streams-inline). |
| `infoHash` | string | Info hash do torrent de origem. |

> Os streams **vêm embutidos** em `videos[].streams` (inline). Quando um vídeo traz `streams`, o Stremio **não** consulta outros addons para ele.

---

## 3. Objeto `video` (+ streams inline)

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | **IMDb ID** casado (ex.: `tt32093575`). |
| `title` | string | Caminho/arquivo dentro do torrent. |
| `released` | string ISO-8601 | Data de adição/lançamento. |
| `thumbnail` | string (URL) | Miniatura. |
| `streams` | array de Stream | Streams reproduzíveis (estrutura como em [stream.md](./stream.md), com `streamData` estendido). |

### `streams[].url` (biblioteca)
Aponta **direto para a API do TorBox**, com `redirect=true` (segue para o arquivo no CDN):

```
https://api.torbox.app/v1/api/torrents/requestdl?token={TOKEN}&torrent_id={id}&file_id={n}&redirect=true
```

- Token do debrid embutido na URL → **deve dispensar headers** → compatível com player externo (Infuse). Mesma propriedade da `url` de `/stream` (essa foi testada: 302→CDN→206; a rota direta da API TorBox não foi testada isoladamente). Ver [stream.md §6](./stream.md#6-comportamento-da-url).
- ⚠️ A URL contém o **token TorBox em texto claro** — trate como segredo (mesma classe da credencial da URL base).

### `streams[].streamData` (extensão AIOStreams, não-padrão)
Mais rico que na rota `/stream`. Campos observados:

| Campo | Exemplo | Significado |
|---|---|---|
| `type` | `"http"` | Tipo da fonte (`http`, `statistic`, …). |
| `proxied` | `false` | Se o stream passa pelo proxy do AIOStreams. |
| `duration` | `0` | Duração (ms); `0` = desconhecida. |
| `library` | `false` | Se é item da biblioteca. |
| `torrent` | `{ private, freeleech }` | Metadados do torrent. |
| `addon` | `"Torrentio"` | Scraper de origem. |
| `keywordMatched` | `false` | Se casou por palavra-chave de filtro. |
| `id` | `"2fe791b-0"` | ID interno do resultado. |

> Não dependa do formato de `streamData` (é interno do AIOStreams). Para reprodução, use apenas `url` + `behaviorHints`.

---

## 4. Prefixos de ID de meta

`manifest.resources[meta].idPrefixes` = `torbox`, `mf`, `dl`, `aiostreamserror`.

| Prefixo | Significado |
|---|---|
| `torbox` | Item da biblioteca TorBox (`torbox:torrents-…`, `torbox:usenet-…`, `torbox:webdl-…`). |
| `mf` | Identificador interno (MediaFusion). |
| `dl` | Identificador interno (downloads). |
| `aiostreamserror` | **Item de erro.** O AIOStreams usa este tipo para reportar falhas como um "meta" navegável (ex.: configuração inválida, erro de scraper), em vez de devolver erro HTTP. Trate como mensagem de diagnóstico, não como conteúdo. *(Formato não capturado em runtime — a validar quando ocorrer.)* |

---

## 5. Uso no StreamHub

- `/meta` é o passo de **detalhe** do fluxo de biblioteca: [`/catalog`](./catalog.md) → `/meta` → reproduzir `videos[].streams[].url`.
- Para "assistir um título por IMDb", **não** use `/meta`; use [`/stream`](./stream.md).
- Aproveite `poster`/`background`/`logo` para a UI de detalhe.
