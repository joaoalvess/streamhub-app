# API de Streams — Addon Stremio (AIOStreams)

> Documentação técnica da API que o **StreamHub** consome nativamente para obter links de reprodução (streams) de filmes, séries e animes. A API é uma instância **self-hosted do addon [AIOStreams](https://github.com/Viren070/AIOStreams)** que segue o **Stremio Addon Protocol**.
>
> Esta pasta é a fonte-da-verdade técnica. Está escrita em PT-BR e otimizada para leitura por agentes de IA: fatos densos, tabelas, exemplos `curl` executáveis e nada de enrolação.

> ⚠️ **CREDENCIAL EMBUTIDA NA URL.** A URL base contém um token de configuração (`{CONFIG}`) que carrega — criptografadas — as chaves de API dos serviços de debrid do usuário. Trate a URL base inteira como **segredo**. Não publique, não logue em texto plano, não envie a serviços externos. As bases reais dos 3 perfis vivem apenas no `StreamHub/Secrets.plist` local (não versionado; template em `Secrets.example.plist`).

---

## 1. O que é esta API

| Atributo | Valor |
|---|---|
| Software | AIOStreams (autor: Viren070) |
| Instâncias | **3 perfis** de configuração no mesmo host (ver [Perfis](#perfis)) |
| Versão | `2.30.3` |
| Hospedagem | Self-hosted, exposto via **Tailscale** (`*.ts.net`) |
| Backend | Node.js / **Express** (`x-powered-by: Express`), HTTP/2 |
| Protocolo | [Stremio Addon Protocol](./protocol.md) |

**AIOStreams é um agregador.** Ele não hospeda vídeo: consulta múltiplos scrapers (Torrentio, StremThru Torz, Comet, MediaFusion, SeaDex, etc.), cruza os resultados com um serviço de **debrid** (nesta instância, **TorBox**) e devolve uma lista unificada de streams já priorizada/filtrada conforme a configuração do perfil. O resultado final são **URLs HTTP(S) diretas e reproduzíveis** — ver [stream.md](./stream.md).

### Perfis

Cada perfil é uma instância de configuração independente (UUID + token próprios) com filtros e
rankings refinados **server-side** — o contrato com o app é: **o 1º stream retornado é sempre o
correto**.

| Perfil | `manifest.name` | UUID da instância | Chave no `Secrets.plist` | Quando o app usa |
|---|---|---|---|---|
| **cinema** | `🎬 Cinema 4K HDR (Legendado)` | `5fd3c25b-cad5-4086-8804-b8e4c9963a3d` | `AIOStreamsCinemaBase` | Modo **Legendado** (Leg) |
| **casual** | `🍿 Casual PT-BR (Dublado)` | `48af64eb-b29a-48a3-add0-4d42f3777bf3` | `AIOStreamsCasualBase` | Modo **Dublado** (Dub) |
| **anime** | `🌸 Anime (Legendado PT-BR)` | `b22a351f-da5e-482b-8841-1bb6c19a1134` | `AIOStreamsAnimeBase` | Todo **anime**, sem modo |

- **Contrato do 1º resultado:** o app toca o **primeiro stream playável** (`url` http(s), sem
  `streamData.statistic`) sem nenhuma seleção client-side (`StreamHub/Streams/StreamProfile.swift`
  + `PlaybackCoordinator`).
- **Detecção de anime no app:** `kind == .anime` (aba Animes) **ou** `contentId` com prefixo
  `mal:`/`kitsu:` **ou** origem Crunchyroll (`streaming.cru`). Anime ignora o modo Dub/Leg e usa
  sempre o perfil anime via `/stream/anime/{id}.json`, com o id do catálogo **como está**
  (funciona com id de série sem episódio, com `:{ep}` e com `tt…` — verificado).
- **Enhanced (futuro):** 1º vídeo do **cinema** + 1º áudio do **casual** unidos por um serviço de
  remux — spec em [../../enhanced/](../../enhanced/README.md).

> **API irmã:** a descoberta de conteúdo (catálogos, fichas, IDs) é feita por outro addon, o **AIOMetadata**, documentado em [`../metadata/`](../metadata/README.md). O fluxo do StreamHub combina os dois: **AIOMetadata** diz *o que assistir* e entrega o ID externo (`tt…`, `mal:…`, `kitsu:…`); **AIOStreams** (esta API) diz *como assistir* (os links). O player (nativo ou Infuse) reproduz.

---

## 2. Anatomia da URL base

Cada **perfil** tem sua própria URL base, todas com esta estrutura:

```
https://spark.tailcb6aa4.ts.net/stremio/5fd3c25b-cad5-4086-8804-b8e4c9963a3d/{CONFIG}
└──────┬─────────────────────┘└───┬──┘└──────────────┬───────────────────┘└───┬───┘
       host (Tailscale)         prefixo          instância (UUID)            token de config
```

| Segmento | Valor | Significado |
|---|---|---|
| `host` | `spark.tailcb6aa4.ts.net` | Host na tailnet, comum aos 3 perfis. Só acessível por dispositivos na mesma rede Tailscale (ou via funnel, se exposto). |
| prefixo | `stremio` | Caminho fixo do AIOStreams. |
| `instância` | um UUID **por perfil** (ver [Perfis](#perfis)) | UUID da instância/perfil no servidor AIOStreams. |
| `{CONFIG}` | `eyJpIjoi…ifQ`, um **por perfil** | **Token de configuração** (ver abaixo). |

### O token `{CONFIG}`

É a "user data inline" do protocolo Stremio (config do usuário carregada na própria URL), implementada pelo AIOStreams com **criptografia**. É um JSON serializado em **base64url**:

```jsonc
// base64url-decode({CONFIG}) =>
{
  "i": "<16 bytes em base64>",   // IV (vetor de inicialização AES, 128 bits)
  "e": "<ciphertext em base64>", // configuração do usuário criptografada (AES)
  "t": "a"                       // tipo/versão do envelope
}
```

- O conteúdo (`e`) contém as credenciais de debrid, scrapers habilitados, regras de ordenação/filtro etc. **Só o servidor AIOStreams consegue decifrar** (a chave fica no servidor). Para o StreamHub o token é **opaco**: copie-o verbatim na URL.
- Cada perfil tem seu próprio token. As **bases completas reais** dos 3 perfis vivem no
  `StreamHub/Secrets.plist` local (não versionado; template em `Secrets.example.plist`).

> Recomendação de implementação: no StreamHub, armazene a **base completa de cada perfil** no Keychain — chaves `AIOStreamsCinemaBase`/`AIOStreamsCasualBase`/`AIOStreamsAnimeBase`, bootstrap via `Secrets.plist` (`StreamHub/Playback/SecretsStore.swift`). Nunca commite as bases fora deste repo interno.

---

## 3. Mapa de rotas

Todas retornam `application/json; charset=utf-8` e terminam em `.json`. `{BASE}` = a URL base da seção 2.

| Recurso | Rota | Descrição | Doc |
|---|---|---|---|
| Manifest | `GET {BASE}/manifest.json` | Capacidades do addon | [manifest.md](./manifest.md) |
| **Stream** | `GET {BASE}/stream/{type}/{id}.json` | **Lista de links de reprodução** (rota central) | [stream.md](./stream.md) |
| Catalog | `GET {BASE}/catalog/{type}/{id}.json` | Catálogos (biblioteca TorBox) | [catalog.md](./catalog.md) |
| Catalog + extra | `GET {BASE}/catalog/{type}/{id}/{extra}.json` | Catálogo paginado (`skip`) | [catalog.md](./catalog.md) |
| Meta | `GET {BASE}/meta/{type}/{id}.json` | Metadados de um item do catálogo | [meta.md](./meta.md) |
| Configure | `GET {BASE}/configure` | Página HTML de configuração (não-JSON) | — |

Exemplo mínimo (a `BASE` de cada perfil está no `StreamHub/Secrets.plist`):

```bash
BASE=$(/usr/libexec/PlistBuddy -c "Print :AIOStreamsCinemaBase" StreamHub/Secrets.plist)
curl -s "$BASE/manifest.json" | jq .
curl -s "$BASE/stream/movie/tt0111161.json" | jq '.streams[0]'
```

---

## 4. Matriz de recursos × tipos

Declarada no [manifest](./manifest.md). Tipos em **negrito** não são padrão do Stremio (são extensões do AIOStreams).

| Recurso | movie | series | **anime** | tv | **events** | **other** |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| `stream` | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| `meta` | ✅ | ✅ | — | ✅ | ✅ | ✅ |
| `catalog` | — | — | — | — | — | ✅ |

- `stream` aceita os prefixos de ID: `tt`, `imdb`, `mal`, `tvdb`, `tmdb`, `kitsu`, `anilist`, `anidb`, `animeplanet`, `anisearch`, `notifymoe`, `mf`, `dl` (lista completa em [id-formats.md](./id-formats.md)).
- `meta`/`catalog` operam sobre a biblioteca do debrid (prefixos `torbox`, `mf`, `dl`) — ver [meta.md](./meta.md) e [catalog.md](./catalog.md).

---

## 5. Características HTTP (importantes para o cliente)

| Característica | Detalhe | Implicação no StreamHub |
|---|---|---|
| **Rate limit** | `5 requisições / 5 s` (`ratelimit-policy: 5;w=5`) | Serializar/limitar chamadas; tratar `429`. Ver [integration.md](./integration.md#4-rate-limiting). |
| CORS | `Access-Control-Allow-Origin: *` | Chamável de qualquer origem. |
| Cache | `ETag` fraco (`W/"…"`) no manifest | Usar `If-None-Match` para `304`. |
| Métodos | `GET, POST, PUT, DELETE, HEAD` | Para consumo, somente `GET`. |
| TLS/HTTP | HTTP/2 | — |

Headers de rate limit retornados em cada resposta: `ratelimit-limit`, `ratelimit-remaining`, `ratelimit-reset` (segundos), `ratelimit-policy`.

---

## 6. Fluxo de uso no StreamHub

```
0.      [AIOMetadata]                        -> descobrir título e obter o ID (tt… / mal:… / kitsu:…)
1.      [app] escolher o perfil              -> anime → anime; modo Dub → casual; modo Leg → cinema
2. GET {BASE do perfil}/stream/{type}/{id}.json -> lista já filtrada e ordenada server-side
3.      tomar o 1º stream playável           -> sem seleção client-side (ver stream.md §10)
4.      reproduzir stream.url                -> handoff para o Infuse
```

> O passo 0 é coberto pela [API de metadados (AIOMetadata)](../metadata/README.md).

- A `stream.url` é uma URL de "resolve" que responde **302 → CDN do TorBox** (token na própria URL) e entrega **206 Partial Content** (Range/seek suportado). Não exige headers. Detalhes em [stream.md](./stream.md#6-comportamento-da-url).
- Para enviar o stream a um player externo (Infuse), ver **[../../player/infuse/](../../player/infuse/README.md)**.

---

## 7. Índice dos arquivos

| Arquivo | Conteúdo |
|---|---|
| [protocol.md](./protocol.md) | Como funciona o Stremio Addon Protocol (rotas, `.json`, extra args, cache, CORS). |
| [manifest.md](./manifest.md) | `/manifest.json` campo a campo, com os valores reais desta instância. |
| [stream.md](./stream.md) | **Rota central.** Objeto stream, tags/emojis, comportamento da `url`, exemplos. |
| [catalog.md](./catalog.md) | `/catalog` e paginação por `skip`. |
| [meta.md](./meta.md) | `/meta` e os prefixos `torbox`/`mf`/`dl`/`aiostreamserror`. |
| [id-formats.md](./id-formats.md) | Todos os formatos de ID aceitos e como montá-los. |
| [integration.md](./integration.md) | Consumo end-to-end no StreamHub (rate limit, cache, seleção, handoff). |

**API irmã (descoberta/metadados):** [../metadata/](../metadata/README.md) — AIOMetadata: catálogos, fichas e os IDs externos consumidos por esta API.

**Player externo:** [../../player/infuse/](../../player/infuse/README.md) — integração com o Infuse.
