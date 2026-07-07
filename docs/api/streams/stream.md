# Rota: `/stream` — links de reprodução

> **Rota central da API.** Recebe um título (por ID externo) e devolve a lista de streams reproduzíveis já agregada de vários scrapers, cruzada com o debrid (TorBox) e ordenada conforme a config (dublado/PT-BR primeiro).

```
GET {BASE}/stream/{type}/{id}.json
Content-Type: application/json; charset=utf-8
```

- `{type}` ∈ `movie`, `series`, `anime`, `tv`, `events`.
- `{id}` conforme [id-formats.md](./id-formats.md). Resumo: filme `tt0111161`; série `tt0903747:1:1`; anime `kitsu:1376:1`.

```bash
curl -s "$BASE/stream/movie/tt0111161.json"      | jq '.streams[0]'
curl -s "$BASE/stream/series/tt0903747:1:1.json" | jq '.streams[0]'
curl -s "$BASE/stream/anime/kitsu:1376:1.json"   | jq '.streams[0]'
```

---

## 1. Envelope da resposta

```json
{ "streams": [ /* itens */ ] }
```

⚠️ **A lista mistura dois tipos de item.** Antes de exibir, é obrigatório separá-los:

| Tipo de item | Reproduzível? | Como reconhecer |
|---|:--:|---|
| **Stream real** | ✅ | Tem `url` (string). **Não** tem `streamData.type == "statistic"`. |
| **Scrape Summary** (informativo) | ❌ | `url` ausente; tem `externalUrl` + `streamData.type == "statistic"`. |

**Filtro recomendado (defensivo):**

```js
const playable = data.streams.filter(
  s => typeof s.url === "string" && s.streamData?.type !== "statistic"
);
```

Em uma chamada observada (`/stream/movie/tt0111161.json`): 23 itens = **18 streams reais** + **5 Scrape Summaries** (um por scraper). O total **varia entre chamadas** (scraping dinâmico/cache) — em outra chamada do mesmo título foram 29 itens.

---

## 2. Objeto Stream (item real)

Exemplo verbatim:

```json
{
  "name": "[TB+] StremThru Torz 2160p",
  "description": "Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv\n💾6.74 GiB 👤5 \n🇵🇹 / 🇬🇧 Subs / 🇧🇷 / 🇬🇧",
  "url": "https://stremthru.13377001.xyz/stremio/torz/…/strem/tt0111161/tb/445bd77…/0/Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv",
  "behaviorHints": {
    "bingeGroup": "com.aiostreams.viren070|torbox|false|2160p|BluRay|HEVC|DD|Portuguese|English|andrehsa",
    "videoHash": "bfdf5ef09715605d",
    "videoSize": 7237543248,
    "filename": "Um.Sonho.de.Liberdade.1994.2160p.Bluray.DD5.1.H265.Dual-andrehsa.mkv"
  }
}
```

| Campo | Tipo | Sempre? | Descrição |
|---|---|:--:|---|
| `name` | string (multi-linha) | ✅ | Rótulo curto. Linha 1: tag de serviço + scraper + qualidade. Linha 2 (opcional): flags de HDR/bit-depth. Ver [§3](#3-anatomia-do-name). |
| `description` | string (multi-linha) | ✅ | Filename + metadados (tamanho, seeds, tracker, idiomas). Ver [§4](#4-anatomia-do-description). |
| `url` | string | ✅ (em itens reais) | URL de reprodução. Comportamento: 302 → CDN → 206. Ver [§6](#6-comportamento-da-url). |
| `behaviorHints` | objeto | ✅ | `bingeGroup` sempre presente; `videoHash`/`videoSize`/`filename` podem variar conforme a fonte. Ver [§5](#5-behaviorhints). |
| `streamData` | objeto | ⚠️ não-padrão | Extensão do AIOStreams. Em `/stream` aparece nos itens **Scrape Summary** como `{ "type": "statistic" }`; o `streamData` descritivo/rico é observado na rota [`/meta`](./meta.md). Pode não aparecer em itens reais de `/stream`. |

> Os campos acima descrevem **itens reais**. Itens **Scrape Summary** (informativos) não têm `url` nem `behaviorHints` — ver [§8](#8-itens-scrape-summary-informativos).
>
> `streamData` **não** faz parte do Stremio Addon Protocol — é uma extensão do AIOStreams. Use-o apenas para o filtro do [§1](#1-envelope-da-resposta); não dependa do seu formato interno.

---

## 3. Anatomia do `name`

```
[TB+] StremThru Torz 2160p      ← linha 1
10bit | HDR                     ← linha 2 (opcional)
```

**Linha 1** = `[{serviço}{indicador}] {scraper} {qualidade}`:

| Parte | Exemplos | Significado |
|---|---|---|
| `[TB+]` | `[TB+]` | Serviço debrid + estado. `TB` = TorBox; `+` = **cacheado/instantâneo** (reprodução imediata). |
| scraper | `StremThru Torz`, `Torrentio`, `Comet` | Origem do resultado (ver [§7](#7-scrapers-observados)). |
| qualidade | `2160p`, `1080p`, `720p`, `Unknown` | Resolução. `Unknown` quando não detectada. |

**Linha 2** (quando presente) = flags visuais de vídeo: `HDR`, `HDR10`, `HDR | DV` (Dolby Vision), `10bit | HDR`, etc.

> A formatação do `name`/`description` é configurável no AIOStreams; trate-a como **texto de exibição**, não como dados estruturados. Para decisões programáticas (qualidade, idioma, codec), prefira parsear o `bingeGroup` ([§5](#5-behaviorhints)) e o `filename`.

---

## 4. Anatomia do `description`

Multi-linha. Padrão observado (linhas podem variar/faltar):

```
Um Sonho de Liberdade 1080p (1994) Dual Áudio BluRay 5.1   ← (opcional) título do release/pasta
Um.Sonho.de.Liberdade.1994.2160p…mkv                       ← filename
💾6.74 GiB 👤5 ⚙️Comando                                    ← métricas
🇵🇹 / 🇬🇧 Subs / 🇧🇷 / 🇬🇧                                  ← idiomas
```

Legenda dos ícones:

| Ícone | Campo | Exemplo |
|---|---|---|
| 💾 | Tamanho do arquivo | `💾6.74 GiB` |
| 👤 | Seeders (origem torrent) | `👤5` |
| ⚙️ | Tracker / fonte do release | `⚙️Comando`, `⚙️EZTV`, `⚙️NyaaSi` |

Idiomas (bandeiras = faixas de **áudio**; sufixos qualificam):

| Token | Significado |
|---|---|
| 🇧🇷 | Áudio Português (Brasil) |
| 🇵🇹 | Áudio Português (Portugal) |
| 🇬🇧 | Áudio Inglês |
| 🇪🇸 / 🇫🇷 | Áudio Espanhol / Francês |
| `… Subs` | É **legenda** naquele idioma (não áudio). Ex.: `🇬🇧 Subs`. |
| `Dual Audio` | Contém duas faixas de áudio (tipicamente original + dublado). |

> Para a política "dublado PT-BR primeiro", os streams com 🇧🇷/🇵🇹 áudio (ou `Dual Audio`) tendem a vir no topo da lista.

---

## 5. `behaviorHints`

| Campo | Tipo | Descrição |
|---|---|---|
| `bingeGroup` | string | Continuidade de **binge watching**: ao avançar para o próximo episódio, o player seleciona implicitamente o stream de mesmo `bingeGroup` (mantém fonte/qualidade). Ver anatomia abaixo. |
| `videoHash` | string | OpenSubtitles hash do vídeo (para casar legendas externas). |
| `videoSize` | number | Tamanho do arquivo em **bytes** (ex.: `7237543248`). |
| `filename` | string | Nome do arquivo de vídeo. **Use este campo** (não a `description`) como nome canônico. |

**Anatomia do `bingeGroup`** (pipe-separated, observado — alguns campos podem variar):

```
com.aiostreams.viren070 | torbox | false | 2160p | BluRay | HEVC | DD | Portuguese | English | andrehsa
└──── addon id ───────┘  └debrid┘ └ flag ┘ └qual.┘ └fonte┘ └vídeo┘ └áudio┘ └──── idiomas ────┘ └grupo┘
```

- Útil para extrair **qualidade, fonte, codec, idiomas** de forma estruturada (mais confiável que o `name`).
- O 3º campo (`false`) é uma flag interna do AIOStreams (significado não confirmado — provavelmente "usenet/p2p"); não dependa dele.

---

## 6. Comportamento da `url`

A `url` **não** aponta direto para o arquivo: é um endpoint de *resolve* do scraper/debrid. Cadeia observada (testada com `curl`):

```
GET stream.url
   ↓ HTTP 302  (location: https://nexus-082.latm.tb-cdn.cx/dld/<id>?token=<token>)
GET <CDN do TorBox>
   ↓ HTTP 206 Partial Content
   content-type: application/octet-stream   • aceita Range (seek)
```

Implicações para reprodução:

| Fato | Consequência |
|---|---|
| Responde **302** para o CDN | O player precisa **seguir redirects** (todos os players sérios seguem). |
| Token vai **na própria URL** do CDN | **Não exige headers** (Authorization/Referer/etc.). ✅ Compatível com players externos como o **Infuse**. |
| CDN entrega **206 / Range** | Seek e buffering progressivo funcionam. |
| `content-type: application/octet-stream` | Container real é `.mkv`/`.mp4` (ver `filename`). Players detectam pelo conteúdo. |
| Hosts de resolve | `stremthru.13377001.xyz`, `torrentio.strem.fun`, `comet.feels.legal`. A `url` testada (StremThru Torz) redirecionou para `*.tb-cdn.cx` (CDN do TorBox); espera-se equivalente nos demais — não verificado um a um. |

> A URL de resolve pode ter validade limitada (token de sessão do debrid). Resolva/reproduza **sob demanda**, perto do play; não cacheie por longos períodos.

Handoff para player externo: ver [../../player/infuse/integration-guide.md](../../player/infuse/integration-guide.md).

---

## 7. Scrapers observados

Cada resultado real traz no `name` o scraper de origem. Observados nesta instância:

| Scraper | Host de resolve | Observação |
|---|---|---|
| StremThru Torz | `stremthru.13377001.xyz` | Torrents via StremThru. |
| Torrentio | `torrentio.strem.fun` | Scraper clássico de torrents. |
| Comet | `comet.feels.legal` | Scraper de torrents. |
| MediaFusion | — | Apareceu apenas em Scrape Summary neste teste. |
| TorBox Search | — | Busca interna do TorBox; summary com 🟠 (warning) neste teste. |

---

## 8. Itens "Scrape Summary" (informativos)

Exemplo verbatim:

```json
{
  "name": "🟢 [Torrentio TB] Scrape Summary",
  "description": "✔ Status      : SUCCESS\n📦 Streams    : 157\n📋 Details    : Successfully fetched streams.\n⏱️ Time       : 617.00ms\n",
  "externalUrl": "https://github.com/Viren070/AIOStreams",
  "streamData": { "type": "statistic" }
}
```

- Um por scraper. Reportam status do scrape: `🟢` = SUCCESS, `🟠` = warning/parcial.
- `description` traz: Status, nº de Streams encontrados, Details, Time.
- Têm `externalUrl` (abre o GitHub do AIOStreams no navegador) — **nunca** são reproduzíveis.
- **Filtrar fora** da lista de reprodução (ver [§1](#1-envelope-da-resposta)). Podem ser úteis para **diagnóstico** (ex.: logar quais scrapers falharam).

---

## 9. Exemplos por tipo

### Filme — `tt0111161`
`[TB+] StremThru Torz 2160p` → `Um.Sonho.de.Liberdade.1994.2160p.Bluray…mkv` (6.74 GiB, áudio 🇵🇹/🇧🇷).

### Série — `tt0903747:1:1`
```json
{
  "name": "[TB+] Torrentio 2160p",
  "description": "Breaking Bad 2008 - 1ª Temporada Completa [4k]…\nBreaking.Bad.S01E01.4K.2160p.WEB-DL.5.1.x264.DUAL…mkv\n💾2.41 GiB 👤6 ⚙️Comando\n🇵🇹 / Dual Audio / 🇪🇸 / 🇬🇧",
  "url": "https://torrentio.strem.fun/resolve/torbox/…/Breaking.Bad.S01E01…mkv",
  "behaviorHints": { "bingeGroup": "com.aiostreams.viren070|torbox|false|2160p|WEB-DL|AVC|…", "videoSize": 2583735246, "filename": "Breaking.Bad.S01E01…mkv" }
}
```

### Anime — `kitsu:1376:1`
```json
{
  "name": "[TB+] Torrentio 1080p",
  "description": "[224] Death Note [BDRip 1080p x265 FLAC]…\n[224] Death Note - 01 [BDRip.1080p.x265.FLAC].mkv\n💾1.06 GiB 👤8 ⚙️NyaaSi\n🇵🇹 / 🇪🇸 / 🇬🇧 / 🇫🇷",
  "url": "https://torrentio.strem.fun/resolve/torbox/…/Death%20Note%20-%2001…mkv",
  "behaviorHints": { "bingeGroup": "com.aiostreams.viren070|torbox|false|1080p|BluRay|HEVC|FLAC|…", "videoSize": 1137353869, "filename": "[224] Death Note - 01 [BDRip.1080p.x265.FLAC].mkv" }
}
```

---

## 10. Seleção de stream (recomendações)

> **StreamHub (atual):** a seleção migrou para o **server-side** — cada perfil do AIOStreams
> (cinema/casual/anime, ver [README §Perfis](./README.md#perfis)) devolve o melhor stream na
> primeira posição e o app toca o **1º playável**. Os critérios abaixo ficam como referência para
> calibrar os perfis.

Para escolher automaticamente o melhor stream:

1. **Filtrar** itens reais (`url` presente, sem `streamData.statistic`) — [§1](#1-envelope-da-resposta).
2. **Validar correspondência** com o título/ano alvo (cruzar `filename` — lembre que ID inválido devolve streams genéricos, ver [id-formats §5](./id-formats.md#5-comportamento-com-id-inválidodesconhecido)).
3. **Preferir cacheado** (`[TB+]`, com `+`) → reprodução instantânea.
4. **Idioma:** priorizar 🇧🇷/🇵🇹 ou `Dual Audio` (alinha com a config do addon).
5. **Qualidade:** ordenar por resolução (`bingeGroup`/`name`), respeitando teto de banda/tela.
6. **Binge:** ao tocar episódios em sequência, manter o mesmo `bingeGroup` para auto-play coerente.

Detalhes de implementação (rate limit, cache, handoff) em [integration.md](./integration.md).
