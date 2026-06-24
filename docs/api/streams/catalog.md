# Rota: `/catalog` — biblioteca do debrid

> Lista o conteúdo **já presente na conta TorBox** do usuário (não é busca por título). É um feed navegável, paginado, do tipo `other`. Para um título específico por IMDb/Kitsu, use [`/stream`](./stream.md), não o catálogo.

```
GET {BASE}/catalog/{type}/{id}.json
GET {BASE}/catalog/{type}/{id}/{extra}.json     # com paginação
```

- `{type}` = sempre `other` nesta instância.
- `{id}` = um dos catálogos declarados no [manifest](./manifest.md#4-catalogs).

---

## 1. Catálogos disponíveis

| `id` | `name` | Conteúdo |
|---|---|---|
| `2fe791b.torrentio-torbox-torrents` | TorBox Torrents | Torrents na biblioteca TorBox |
| `2fe791b.torrentio-torbox-usenet` | TorBox Usenet | Downloads via Usenet |
| `2fe791b.torrentio-torbox-webdl` | TorBox WebDL | Downloads diretos (WebDL) |

```bash
curl -s "$BASE/catalog/other/2fe791b.torrentio-torbox-torrents.json" | jq '.metas | length'
```

---

## 2. Resposta

Envelope `{ "metas": [ … ] }` com **Meta Preview** minimalista (só os campos essenciais — sem poster no catálogo):

```json
{
  "metas": [
    { "id": "torbox:torrents-44797938", "type": "other", "name": "Scary.Movie.2026.1080p.CAMRip.Dublado.V.3.mkv" },
    { "id": "torbox:torrents-41668286", "type": "other", "name": "Witch.Hat.Atelier.S01E02.1080p.CR.WEB-DL.AAC2.0.H.264.DUAL-BiOMA" }
  ]
}
```

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | string | ID do item. Formato `torbox:{categoria}-{torrentId}` (ex.: `torbox:torrents-44797938`). Use-o em [`/meta`](./meta.md). |
| `type` | string | `other`. |
| `name` | string | Nome do release/arquivo. |

> Diferente do protocolo padrão, os Meta Previews aqui **não** trazem `poster`. Para obter poster/background/streams, faça uma chamada a [`/meta`](./meta.md) com o `id`.

---

## 3. Paginação (`skip`)

Único `extra` suportado. Formato: segmento `skip=N` antes do `.json` (ver [protocol §3](./protocol.md#3-extra-args-paginação-busca-filtro)).

```bash
curl -s "$BASE/catalog/other/2fe791b.torrentio-torbox-torrents/skip=100.json" | jq '.metas | length'
```

- `skip` = quantos itens pular desde o início.
- **Heurística de fim:** quando a página retorna poucos itens (bem abaixo do lote inicial), não há mais páginas. Observado: uma chamada sem `skip` retornou 128 itens (esta instância pode devolver lotes **acima** do padrão de 100 do Stremio); uma chamada com `skip=100` retornou 40. Use a heurística "poucos itens = fim", não um total fixo.
- ⚠️ **Conteúdo volátil:** a biblioteca muda em tempo real (novos downloads). Contagens e ordem **não são estáveis** entre chamadas; não pagine assumindo um total fixo.

---

## 4. Uso no StreamHub

```
/catalog/other/{catálogo}.json        -> lista a biblioteca (ids + nomes)
   ↓ (paginar com /skip=N.json conforme rola a lista)
/meta/other/{id}.json                 -> detalhes + streams inline do item
   ↓
reproduzir video.streams[].url        -> ver meta.md
```

Use o catálogo para a tela "Minha biblioteca / Downloads". Para "assistir um filme X", o caminho é [`/stream`](./stream.md), não o catálogo.
