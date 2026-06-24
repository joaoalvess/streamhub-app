# API de Streams — Addon Stremio (AIOStreams)

> Documentação técnica da API que o **StreamHub** consome nativamente para obter links de reprodução (streams) de filmes, séries e animes. A API é uma instância **self-hosted do addon [AIOStreams](https://github.com/Viren070/AIOStreams)** que segue o **Stremio Addon Protocol**.
>
> Esta pasta é a fonte-da-verdade técnica. Está escrita em PT-BR e otimizada para leitura por agentes de IA: fatos densos, tabelas, exemplos `curl` executáveis e nada de enrolação.

> ⚠️ **CREDENCIAL EMBUTIDA NA URL.** A URL base contém um token de configuração (`{CONFIG}`) que carrega — criptografadas — as chaves de API dos serviços de debrid do usuário. Trate a URL base inteira como **segredo**. Não publique, não logue em texto plano, não envie a serviços externos. Os exemplos abaixo usam a URL real apenas porque este repositório é interno.

---

## 1. O que é esta API

| Atributo | Valor |
|---|---|
| Software | AIOStreams (autor: Viren070) |
| `manifest.name` | `AIOStream` |
| `manifest.id` | `com.aiostreams.viren070.8b977f8f-511` |
| Versão | `2.30.3` |
| Descrição | "AIOStreams configurado para priorizar conteudo dublado em PT-BR." *(string literal do manifest — sem acento no original)* |
| Hospedagem | Self-hosted, exposto via **Tailscale** (`*.ts.net`) |
| Backend | Node.js / **Express** (`x-powered-by: Express`), HTTP/2 |
| Protocolo | [Stremio Addon Protocol](./protocol.md) |

**AIOStreams é um agregador.** Ele não hospeda vídeo: consulta múltiplos scrapers (Torrentio, StremThru Torz, Comet, MediaFusion, etc.), cruza os resultados com um serviço de **debrid** (nesta instância, **TorBox**) e devolve uma lista unificada de streams já priorizada/filtrada conforme a configuração do usuário (aqui: priorizar dublado PT-BR). O resultado final são **URLs HTTP(S) diretas e reproduzíveis** — ver [stream.md](./stream.md).

> **API irmã:** a descoberta de conteúdo (catálogos, fichas, IDs IMDb) é feita por outro addon, o **AIOMetadata**, documentado em [`../metadata/`](../metadata/README.md). O fluxo do StreamHub combina os dois: **AIOMetadata** diz *o que assistir* e entrega o ID externo (`tt…`); **AIOStreams** (esta API) diz *como assistir* (os links). O player (nativo ou Infuse) reproduz.

---

## 2. Anatomia da URL base

Todas as rotas penduram em uma **URL base** com esta estrutura:

```
https://spark.tailcb6aa4.ts.net/stremio/8b977f8f-511e-4a0a-93ab-eee540af8cb6/{CONFIG}
└──────┬─────────────────────┘└───┬──┘└──────────────┬───────────────────┘└───┬───┘
       host (Tailscale)         prefixo          instância (UUID)            token de config
```

| Segmento | Valor nesta instância | Significado |
|---|---|---|
| `host` | `spark.tailcb6aa4.ts.net` | Host na tailnet. Só acessível por dispositivos na mesma rede Tailscale (ou via funnel, se exposto). |
| prefixo | `stremio` | Caminho fixo do AIOStreams. |
| `instância` | `8b977f8f-511e-4a0a-93ab-eee540af8cb6` | UUID da instância/usuário no servidor AIOStreams. |
| `{CONFIG}` | `eyJpIjoi…ifQ` | **Token de configuração** (ver abaixo). |

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
- Valor real desta instância (segredo):
  ```
  eyJpIjoicWhoeXRrbDN1QjlUYmt0S21mMk10QT09IiwiZSI6ImFJb3lkTzRFVmdPTlNwSkN0Mzh0cHNOSUZ4a0FKTC9EYWVIdVpjTFRlMmc9IiwidCI6ImEifQ
  ```

> Recomendação de implementação: no StreamHub, armazene `host`, `uuid` e `CONFIG` separadamente (ex.: Keychain) e monte a URL base em runtime. Nunca commite a base completa fora deste repo interno.

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

Exemplo mínimo:

```bash
BASE="https://spark.tailcb6aa4.ts.net/stremio/8b977f8f-511e-4a0a-93ab-eee540af8cb6/eyJpIjoicWhoeXRrbDN1QjlUYmt0S21mMk10QT09IiwiZSI6ImFJb3lkTzRFVmdPTlNwSkN0Mzh0cHNOSUZ4a0FKTC9EYWVIdVpjTFRlMmc9IiwidCI6ImEifQ"
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
0.      [AIOMetadata]               -> descobrir título e obter o ID externo (IMDb tt…)
1. (1x) GET /manifest.json          -> descobrir capacidades/tipos suportados
2. GET /stream/{type}/{id}.json      -> lista de streams candidatos
3.      [filtrar + selecionar]       -> por qualidade/idioma/cache (ver stream.md §seleção)
4.      reproduzir stream.url        -> player nativo OU handoff para o Infuse
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
