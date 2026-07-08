---
titulo: "Referência do esquema infuse:// e x-callback-url"
parte_de: "docs/player/infuse"
objetivo: "Referência completa e verbatim do esquema de URL do Infuse: ações play/save, deep links TMDB, todos os parâmetros, callbacks e regras de encoding."
ordem: 1
tipo: referencia
relevancia_para_streamhub: alta
atualizado_em: "2026-07-08"
fontes_oficiais:
  - "https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services"
  - "https://x-callback-url.com/specification/"
fontes_comunidade:
  - "https://community.firecore.com/t/can-the-argument-in-the-infuse-api-url-be-located-on-a-share/45786"
versao_infuse_referencia: "8.4.7+"
---

# Referência do esquema `infuse://` e `x-callback-url`

## TL;DR

- Esquema base: **`infuse://`**. Há duas famílias de uso:
  1. **Ações x-callback-url** — `infuse://x-callback-url/play?...` e `infuse://x-callback-url/save?...` (reproduzir / salvar URLs de vídeo).
  2. **Deep links TMDB** — `infuse://movie/{tmdb_id}`, `infuse://series/{tmdb_id}` (abrir um item da biblioteca por TMDB ID).
- Para o StreamHub o que importa é **`/play`**: ele recebe `url` (do stream), opcionalmente `position` (resume), `filename` (metadados via nome de arquivo), `sub` (legenda externa) e os callbacks `x-success` / `x-error`.
- **`url` aceita apenas HTTP/HTTPS.** SMB/NFS/UPnP/FTP/magnet **não** são aceitos no parâmetro `url` (confirmação verbatim de staff Firecore — ver §6).
- **Todos os valores de querystring devem ser URL-encoded** (percent-encoding). A própria `url` do vídeo e as URLs de callback precisam ser encodadas.
- O `x-success` do `/play` retorna **`lastPlayedUrl`** e **`position`** (segundos) quando a reprodução/playlist termina ou o player é fechado — é assim que o StreamHub recebe de volta a posição.
- Versão oficial de referência: **Infuse 8.4.7+** (a página oficial fixa essa versão para o conjunto completo, incluindo Apple TV). Histórico de versões em [platforms.md](./platforms.md) e [limitations.md](./limitations.md).

> Esta página reproduz **verbatim** os exemplos e parâmetros da página oficial "API for Third-Party Apps & Services" (Firecore Support). Onde um fato vier de fórum/comunidade ou for inferido, está marcado **[COMUNIDADE]** ou **[INFERIDO / a validar]**.

---

## 1. Visão geral das ações

| Ação | Esquema | Finalidade | Callback útil |
|---|---|---|---|
| **play** | `infuse://x-callback-url/play?...` | Reproduzir 1+ vídeos imediatamente como playlist temporária e voltar ao app de origem ao terminar. | `x-success` retorna `lastPlayedUrl` + `position`. |
| **save** | `infuse://x-callback-url/save?...` | Salvar (bookmark) 1+ URLs na biblioteca para tocar depois; opcionalmente baixar para offline. | `x-success` **sem parâmetros**. |
| **deep link (movie)** | `infuse://movie/{tmdb_id}` | Abrir a página de um filme na biblioteca (ou placeholder com dados TMDB). | — |
| **deep link (series)** | `infuse://series/{tmdb_id}` | Abrir a página de uma série. | — |
| **deep link (season)** | `infuse://series/{tmdb_id}-{season_number}` | Abrir uma temporada. | — |
| **deep link (episode)** | `infuse://series/{tmdb_id}-{season_number}-{episode_number}` | Abrir um episódio. | — |

Fonte (todas as linhas): página oficial "API for Third-Party Apps & Services" — https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services

---

## 2. Ação `play` — reproduzir vídeos

> "Play one or more videos and return to another app when finished" — oficial.

### 2.1. Exemplo oficial (verbatim)

Reproduzido exatamente como na documentação oficial (quebras de linha apenas para leitura; numa URL real não há quebras nem espaços):

```text
infuse://x-callback-url/play?url=https://files.firecore.com/infuse/sample-5s-360p.mp4&
position=0&
filename=Inception-2010.mp4&
sub=https://files.firecore.com/infuse/example.srt&
url=https://files.firecore.com/infuse/mov_bbb.mp4&
position=6&
filename=Mad-Men-S01-E01.mp4&
sub=https://files.firecore.com/infuse/example2.srt&
x-success=some-app://success&
x-error=some-app://error
```

Repare que o exemplo passa **dois vídeos** (dois pares `url`/`position`/`filename`/`sub`) — uma playlist temporária.

> ⚠️ **Atenção:** o exemplo oficial mostra as `url`/`sub` **sem** percent-encoding por legibilidade, mas a própria doc avisa que isso só "funciona em alguns casos" e que com múltiplos parâmetros você **precisa encodar manualmente** (ver §5). Na prática, **sempre encode** os valores.

### 2.2. Parâmetros do `play`

| Parâmetro | Obrigatório | Repetível | Tipo / formato | Descrição |
|---|---|---|---|---|
| `url` | **Sim** | **Sim** | HTTP/HTTPS (string encodada) | URL do vídeo. Múltiplas ocorrências = playlist sequencial. |
| `position` | Não | Sim (1 por `url`) | inteiro (segundos) | Posição inicial / resume. "Specifying a position value (expressed as an integer number of seconds) will cause the video to start/resume from the specified position." |
| `filename` | Não | Sim (1 por `url`) | string | Nome de arquivo sugerido. Ajuda o Infuse a buscar metadados corretos no TMDB se seguir os [naming styles recomendados](https://support.firecore.com/hc/articles/215090947-Metadata-101). |
| `sub` | Não | Sim (1 por `url`) | URL de legenda (HTTP/HTTPS) | Legenda externa (sidecar). Ver [limitations.md](./limitations.md) sobre formatos. |
| `x-success` | Não | Não | URL de callback (encodada) | App de origem a abrir quando a reprodução termina/fecha. |
| `x-error` | Não | Não | URL de callback (encodada) | App de origem a abrir em caso de erro. |

Fonte: seção "Sending Videos to Infuse for Playback" — https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services

### 2.3. Notas oficiais do `play` (verbatim)

- "Supports single or multiple url entries"
- "Subtitle, filename, and position parameters are optional"
- "Specifying a filename can help provide accurate metadata when using one of the recommended file naming styles"
- "Specifying a position value (expressed as an integer number of seconds) will cause the video to start/resume from the specified position"
- "All URLs are played sequentially as a temporary playlist"
- "x-success is not called for each individual URL in the list, but once when playlist playback ends or when the player is closed. Returns last URL + position (in seconds)."
- "x-error is called once and returns failed URLs (invalid or playback errors)"

### 2.4. Correspondência posicional dos parâmetros repetíveis

Como `url`, `position`, `filename` e `sub` são todos repetíveis, eles se **associam pela ordem de aparição** na querystring (1º `url` ↔ 1º `position` ↔ 1º `filename` ↔ 1º `sub`, e assim por diante). Isso é o que o exemplo oficial demonstra. **[INFERIDO a partir do exemplo oficial]** — a doc não descreve explicitamente o algoritmo de pareamento, apenas mostra o padrão. Para o StreamHub (que tipicamente envia **um único stream**), isso é irrelevante; envie um `url` e, se quiser, um `position`/`filename`/`sub`.

---

## 3. Ação `save` — salvar / baixar

> "Save (bookmark) one or more video URL to play later"

### 3.1. Exemplo oficial (verbatim)

```text
infuse://x-callback-url/save?
url=https://files.firecore.com/infuse/sample-5s-360p.mp4&
filename=Inception-2010.mp4&
sub=https://files.firecore.com/infuse/example1.srt&
url=https://files.firecore.com/infuse/mov_bbb.mp4&
filename=Mad-Men-S01-E01.mp4&
sub=https://files.firecore.com/infuse/example2.srt&
download=0&
x-success=some-app://success&
x-error=some-app://error
```

### 3.2. Parâmetros do `save`

| Parâmetro | Obrigatório | Repetível | Tipo / formato | Descrição |
|---|---|---|---|---|
| `url` | **Sim** | **Sim** | HTTP/HTTPS (encodada) | URL do vídeo a salvar. |
| `filename` | Não | Sim | string | Nome de arquivo (metadados via naming style). |
| `sub` | Não | Sim | URL de legenda | Legenda externa. |
| `download` | Não | Não (vale para a requisição inteira) | `0` ou `1` | `0` = salvar o link apenas; `1` = salvar o link **e** baixar para reprodução offline. |
| `x-success` | Não | Não | URL de callback | Chamado ao concluir; **sem parâmetros**. |
| `x-error` | Não | Não | URL de callback | Chamado uma vez com URLs que falharam. |

### 3.3. Notas oficiais do `save` (verbatim)

- "Supports single or multiple url entries"
- "Subtitle and filename parameters are optional"
- "Specifying a filename can help provide accurate metadata when using one of the recommended file naming styles"
- "Download parameter can be used to begin downloading files for offline playback (0=save link only, 1=save link and download)"
- "Download parameter applies to the entire request"
- "x-success has no parameters"
- "x-error is called once and returns failed URLs (EG invalid links)"

> **Relevância p/ StreamHub:** `save` é útil se quisermos uma ação "Adicionar ao Infuse para ver depois / baixar offline". Para o fluxo principal ("abrir e tocar agora"), use `play`.

---

## 4. Callbacks (x-success / x-error)

O Infuse usa o padrão **x-callback-url** (spec: https://x-callback-url.com/specification/). Ao terminar a ação, o Infuse **abre** a URL que você passou em `x-success` (ou `x-error`), anexando parâmetros de retorno. O seu app deve registrar o esquema dessas URLs para recebê-las.

### 4.1. `play` → `x-success` (verbatim)

```text
some-app://success?lastPlayedUrl=https://files.firecore.com/infuse/mov_bbb.mp4&
position=8
```

| Parâmetro retornado | Significado |
|---|---|
| `lastPlayedUrl` | A última `url` que estava tocando quando o player fechou. |
| `position` | Posição (em **segundos**) no momento do fechamento. |

> É **uma única chamada** ao final da playlist ou quando o player é fechado (não uma por vídeo). É exatamente o gancho de **resume** para o StreamHub persistir o progresso.

### 4.2. `play` / `save` → `x-error` (verbatim)

```text
some-app://error?errorCode=100&
errorMessage=Unsupported%20content&
failedUrl=invalid_url1&
failedUrl=invalid_url2
```

| Parâmetro retornado | Significado |
|---|---|
| `errorCode` | Código numérico do erro (ex.: `100`). |
| `errorMessage` | Mensagem (já vem URL-encoded, ex.: `Unsupported%20content`). |
| `failedUrl` | URL(s) que falharam. **Repetível** (uma por URL com falha). |

> ⚠️ **[a validar]** A doc oficial só exemplifica `errorCode=100` ("Unsupported content"). **Não há tabela oficial de códigos de erro.** Trate `errorCode` como opaco e use `errorMessage` para log; não dependa de valores específicos sem testar.

### 4.3. `save` → `x-success` (verbatim)

```text
some-app://success
```

Sem parâmetros.

### 4.4. Modelo mental do x-callback-url

- `x-source` (nome do app de origem, exibível) é parte da **spec** do x-callback-url, mas **não aparece** nos exemplos oficiais do Infuse. **[a validar]** — não assuma que o Infuse lê/usa `x-source`; a doc dele só cita `x-success` e `x-error`.
- O Infuse **não documenta** `x-cancel`. **[a validar]** — se o usuário cancelar/fechar, o comportamento observado é cair em `x-success` com a `position` atual (ver nota verbatim "or when the player is closed").

---

## 5. Encoding de URL (obrigatório)

Da seção oficial "URL Encoding":

> "Per the x-callback-url spec, all querystring values should be url-safe or encoded. Unencoded URLs may work in some cases, but when using actions with multiple parameters or URLs with multiple keys you will probably need to manually encode your URLs."

Exemplos oficiais:

| Estado | Valor |
|---|---|
| **Unencoded** | `http://192.168.162.100/Movies/movie.mkv` |
| **Encoded** | `http%3A%2F%2F192.168.162.100%2FMovies%2Fmovie.mkv` |

Regras práticas para o StreamHub:

1. **Percent-encode o valor de cada parâmetro** (`url`, `sub`, `x-success`, `x-error`, `filename`) — não a URL inteira do `infuse://`.
2. Use um conjunto de caracteres permitidos que **exclua** `&`, `=`, `?`, `/`, `:` dos valores. ⚠️ Em Swift, o setter `queryItems` do `URLComponents` **não cumpre essa regra**: ele escapa `&`/`=`/`%`, mas deixa `?`, `:` e `/` **crus** nos valores (são válidos em query por RFC 3986). Encode cada valor integralmente para o conjunto unreserved (`A-Za-z0-9-._~`) com `addingPercentEncoding` e monte via `percentEncodedQueryItems` — é o formato do exemplo "Encoded" oficial acima. Ver [integration-guide.md](./integration-guide.md) §3.
3. URLs de debrid/resolvers costumam ter query strings próprias (`?token=...&exp=...`) — sem encoding total, o parser do Infuse mutila o valor no `?` cru da URL interna (comprovado com URLs do Comet: sem a query interna o resolver responde `422` e o Infuse dispara `x-error`).

---

## 6. Protocolos aceitos no parâmetro `url`

**Confirmado: apenas HTTP e HTTPS.**

> **[COMUNIDADE — staff Firecore, verbatim]** james (Firecore), 2023-11-06: *"It can be any http link as long as it is accessible from your current location. SMB, NFS, UPnP, etc… cannot be used here."*
> Fonte: https://community.firecore.com/t/can-the-argument-in-the-infuse-api-url-be-located-on-a-share/45786

| Tipo de fonte | Aceito no `url=` do esquema? | Observação |
|---|---|---|
| HTTP/HTTPS → mp4/mkv direto | **Sim** | Caso principal (debrid TorBox/RealDebrid). |
| HTTPS → HLS (`.m3u8`) | **[a validar]** | É HTTP-based, logo cairia em "any http link"; mas **não há exemplo/afirmação oficial** confirmando `.m3u8` via esquema. Testar. |
| magnet / torrent | **Não** | Não é HTTP. Use outro player ou resolva via debrid antes. |
| FTP / FTPS / SFTP | **Não** (via esquema) | Suportado pelo app como fonte de biblioteca, mas não no `url=`. |
| SMB / NFS / UPnP / DLNA / WebDAV | **Não** (via esquema) | Idem — confirmado pelo quote do staff. |

> **Distinção importante:** o **app Infuse** suporta uma gama enorme de fontes (SMB, NFS, FTP, UPnP/DLNA, WebDAV, Plex/Emby/Jellyfin, cloud). Mas o **esquema `infuse://...play?url=`** é restrito a **HTTP(S)**. Não confunda as duas coisas. Ver [limitations.md](./limitations.md).

---

## 7. Deep links TMDB (`infuse://movie` / `infuse://series`)

Da seção oficial "Deep Linking to Infuse Library Items":

> "Apps can link directly to items in the Infuse library using the appropriate TMDB ID numbers. Note: If a title is not present in the library, a placeholder page with TMDB data will be shown."

| Alvo | Formato | Exemplo |
|---|---|---|
| Filme | `infuse://movie/{tmdb_id}` | `infuse://movie/27205` |
| Série | `infuse://series/{tmdb_id}` | `infuse://series/1396` |
| Temporada | `infuse://series/{tmdb_id}-{season_number}` | `infuse://series/1396-1` |
| Episódio | `infuse://series/{tmdb_id}-{season_number}-{episode_number}` | `infuse://series/1396-1-1` |

### 7.1. `?play` (opcional, verbatim)

> "Add the **?play** parameter to the end of a deep link to automatically start playback of the linked library item."
> Exemplo oficial: `infuse://movie/1327819?play`

> **Relevância p/ StreamHub:** os deep links TMDB **abrem um item da biblioteca do Infuse** (ou um placeholder TMDB) — eles **não recebem a URL de um stream do scraper**. Só são úteis se o conteúdo já estiver na biblioteca do Infuse (ex.: via STRM/STRMLNK ou sync). Para "abrir a URL deste stream agora", use **`/play`** (§2). Note ainda que o ID aqui é **TMDB**, enquanto os addons do StreamHub usam majoritariamente **IMDb (`tt...`)** — seria necessário converter IMDb→TMDB. Ver [limitations.md](./limitations.md).

---

## 8. Resumo de capacidades por parâmetro (cheat sheet)

| Quero passar... | Como | Suportado? |
|---|---|---|
| URL do vídeo | `url=` (HTTP/HTTPS, encodada) | **Sim** |
| Resume / posição inicial | `position=` (segundos, inteiro) | **Sim** |
| Título do conteúdo | `filename=` (nome de arquivo p/ TMDB) | **Parcial** — não é "título" livre; é nome de arquivo que dispara lookup TMDB. Ver [limitations.md](./limitations.md). |
| Legenda externa | `sub=` (URL HTTP/HTTPS) | **Sim** |
| Poster / artwork | — | **Não** — nenhum parâmetro de poster no esquema `/play`. |
| Descrição / sinopse | — | **Não** — só via TMDB (a partir do `filename`). |
| Headers HTTP (Authorization, Referer, etc.) | — | **Não** — nenhum parâmetro de header. Ver [limitations.md](./limitations.md). |
| Receber posição ao sair | `x-success` → `lastPlayedUrl` + `position` | **Sim** |
| Múltiplos vídeos (playlist) | `url=` repetido | **Sim** |
| Magnet / torrent | — | **Não** (só HTTP/HTTPS). |

---

## Fontes

- **[OFICIAL]** "API for Third-Party Apps & Services" (fonte primária, verbatim) — https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services
  - Slug legado equivalente (mesmo article ID 215090997): `.../215090997-Callback-URLs-iOS-only-`
- **[OFICIAL]** x-callback-url specification — https://x-callback-url.com/specification/
- **[OFICIAL]** Metadata 101 (naming styles que o `filename` aproveita) — https://support.firecore.com/hc/articles/215090947-Metadata-101
- **[COMUNIDADE]** Limite de protocolo do `url` (quote de staff) — https://community.firecore.com/t/can-the-argument-in-the-infuse-api-url-be-located-on-a-share/45786
