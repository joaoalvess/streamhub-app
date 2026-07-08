---
titulo: "Integração do player Infuse — Documentação StreamHub"
parte_de: "docs/player/infuse"
objetivo: "Índice e visão geral de como o StreamHub abre streams no player externo Infuse (Firecore) via esquema infuse:// / x-callback-url, com resumo de capacidades e limitações por plataforma."
ordem: 0
tipo: indice
relevancia_para_streamhub: alta
atualizado_em: "2026-07-08"
fontes_oficiais:
  - "https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services"
  - "https://firecore.com/releases"
  - "https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)"
versao_infuse_referencia: "8.4.7+"
---

# Integração do player Infuse — Documentação StreamHub

> **Para a IA que vai ler isto:** esta pasta é a fonte da verdade sobre como o **StreamHub** abre
> um stream no **Infuse** (player externo da Firecore) via o esquema de URL `infuse://`. Cada arquivo
> é autocontido, começa com frontmatter YAML e um bloco `## TL;DR`, e cita a URL da fonte sempre que
> afirma um fato. Fatos são marcados **[OFICIAL]** (firecore.com / support.firecore.com / Apple docs),
> **[COMUNIDADE]** (fórum community.firecore.com / GitHub), **[OFICIAL-derivado/implied]** ou
> **[INFERIDO / a validar]**. Nunca trate algo marcado "a validar" como contrato estável sem testar.

## Contexto do StreamHub (leia primeiro)

O StreamHub é um app **SwiftUI para tvOS** (ver `docs/addons/README.md`) que consome addons do
Stremio nativamente. Um addon scraper (AIOStreams) retorna, para um filme/episódio, uma lista de
**streams** — tipicamente **URLs HTTP/HTTPS de debrid** (TorBox, RealDebrid) apontando para arquivos
de vídeo já cacheados (mp4/mkv), às vezes HLS (`.m3u8`), às vezes magnet, com legendas/metadados.

**Objetivo desta integração:** quando o usuário escolhe um stream, abrir essa **URL de vídeo
diretamente no Infuse** (player externo), passando o máximo de metadados possível (título via nome de
arquivo, legenda externa, posição de resume) e, se possível, **receber de volta** a posição quando o
usuário sai do Infuse.

**Mecanismo central:** o esquema **`infuse://x-callback-url/play?url=...`** (ação `play`), com
callbacks `x-success`/`x-error` no padrão [x-callback-url](https://x-callback-url.com/specification/).

## Como ler (ordem recomendada)

| # | Arquivo | Objetivo | Relevância |
|---|---|---|---|
| 1 | [url-schemes.md](./url-schemes.md) | Referência completa e **verbatim** do esquema `infuse://`: ações `play`/`save`, deep links TMDB, todos os parâmetros, callbacks, encoding, protocolos aceitos. | **alta** |
| 2 | [integration-guide.md](./integration-guide.md) | Passo a passo em **Swift**: mapear `Stream`→URL, montar o `infuse://` com `URLComponents`, detectar instalação (`canOpenURL`/`LSApplicationQueriesSchemes`), abrir e tratar callbacks. | **alta** |
| 3 | [platforms.md](./platforms.md) | Diferenças **iOS/iPadOS/tvOS/macOS/visionOS** — com foco no **tvOS** (alvo) e no histórico de versões. | **alta** |
| 4 | [limitations.md](./limitations.md) | Limitações e riscos: **headers/debrid**, sem poster, protocolos não suportados, requisitos de versão/Pro, e **workarounds** (STRM/STRMLNK, player nativo). | **alta** |

Caminho mínimo p/ implementar: **url-schemes.md → integration-guide.md → limitations.md §1 (headers)**.

## Resumo de capacidades (1 minuto)

Esquema-alvo (exemplo real, com **um** stream, valores que numa URL real estariam percent-encoded):

```text
infuse://x-callback-url/play?url=https%3A%2F%2Fabc.torbox.app%2Fdl%2Fxyz%2FInception.mkv%3Ftoken%3D...&position=845&filename=Inception%20(2010).mkv&sub=https%3A%2F%2Fexample%2Finception.pt-BR.srt&x-success=streamhub%3A%2F%2Finfuse%2Fsuccess&x-error=streamhub%3A%2F%2Finfuse%2Ferror
```

| Quero... | Suportado? | Como |
|---|---|---|
| Abrir uma URL de vídeo HTTP/HTTPS | **Sim** | `url=` (ação `play`) |
| Resume (posição inicial) | **Sim** | `position=` em segundos |
| Receber posição ao sair | **Sim** (Infuse 8.4.6+) | `x-success` → `lastPlayedUrl` + `position` |
| Legenda externa | **Sim** | `sub=` (URL) |
| Título do conteúdo | **Parcial** | `filename=` (dispara lookup TMDB por nome de arquivo) |
| Poster / descrição | **Não** | sem parâmetro no esquema |
| Headers HTTP (Authorization/Referer) | **Não** | sem parâmetro; ver risco abaixo |
| Magnet / SMB / NFS / FTP no `url` | **Não** | só HTTP/HTTPS |
| HLS `.m3u8` no `url` | **[a validar]** | "any http link" deveria cobrir; sem confirmação oficial |
| Salvar p/ ver depois / baixar offline | **Sim** | ação `save` (`download=0|1`) |
| Deep link a item da biblioteca | **Sim** (TMDB ID) | `infuse://movie|series/{tmdb_id}` — **não** recebe URL de stream |

Fonte de todas as linhas acima: [url-schemes.md](./url-schemes.md), derivado da página oficial
https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services

## Capacidades e limitações por plataforma

| Plataforma | `infuse://...play` | Deep link TMDB | Detecção (`canOpenURL`) | Risco p/ StreamHub |
|---|---|---|---|---|
| **tvOS** (alvo) | **Sim** (8.4.7+; historicamente iOS-only) | Sim (≥ 8.2.3) | Sim, com caveats | **Médio** — validar em device; fallback nativo |
| iOS / iPadOS | Sim | Sim | Sim (c/ `LSApplicationQueriesSchemes`) | Baixo |
| macOS | Sim | Sim | Sim (via AppKit/`NSWorkspace`) | Baixo-médio |
| visionOS | Sim | Sim | Sim | Baixo |

Detalhe e citações em [platforms.md](./platforms.md). Linha oficial: *"Available platforms: iPhone,
iPad, Apple TV, Mac, and Vision"* / *"Infuse version: 8.4.7 (or later)"*.

## Os 3 riscos que mais importam (ver [limitations.md](./limitations.md))

1. **Headers HTTP não passam pelo esquema.** Mitigado porque links de debrid são URLs HTTPS
   pré-autenticadas (token na URL) e dispensam headers — o caso comum funciona. URLs que exijam
   header custom **falham**: para essas, usar o player nativo.
2. **tvOS (alvo):** o esquema é oficialmente suportado, mas a **detecção/abertura/callback entre
   apps** no tvOS precisam de validação em Apple TV físico; features chegam ao tvOS depois do iOS.
3. **Metadados pobres:** só `filename` (→ TMDB). Sem poster/descrição/título-livre via esquema.

## Decisões já tomadas / recomendações

- **Exigir Infuse 8.4.7+** para a experiência completa (resume bidirecional desde 8.4.6; API tvOS
  amadureceu no 8.x).
- **Filtrar streams**: só oferecer "Abrir no Infuse" quando `stream.url` for HTTP/HTTPS (excluir
  magnet/`infoHash`).
- **Sempre ter fallback** para o **player nativo** do StreamHub (cobre magnet/HLS/headers e o caso
  "Infuse não instalado" / cross-app falho no tvOS).
- **Montar a URL encodando cada valor integralmente** (unreserved RFC 3986, via `percentEncodedQueryItems`) — o setter `queryItems` deixa `?`/`:`/`/` crus e o Infuse mutila URLs com query interna; nunca concatenação de string.

## Glossário (termos canônicos)

| Termo | Definição |
|---|---|
| **esquema `infuse://`** | URL scheme do app Infuse, registrado pelo app no sistema. |
| **x-callback-url** | Convenção (spec https://x-callback-url.com) para apps se chamarem e retornarem resultado via URLs `x-success`/`x-error`. O Infuse a implementa. |
| **ação `play`** | `infuse://x-callback-url/play?...` — reproduzir 1+ URLs como playlist temporária. |
| **ação `save`** | `infuse://x-callback-url/save?...` — bookmark/baixar 1+ URLs. |
| **deep link TMDB** | `infuse://movie|series/{tmdb_id}` — abrir item da biblioteca por TMDB ID (não recebe URL de stream). |
| **`url`** | Parâmetro da ação play/save: a URL HTTP/HTTPS do vídeo. |
| **`position`** | Posição em **segundos** (resume): enviada no `play`, retornada no `x-success`. |
| **`filename`** | Nome de arquivo sugerido; dispara lookup de metadados no TMDB se seguir naming styles. |
| **`sub`** | URL de legenda externa (sidecar). |
| **`x-success` / `x-error`** | URLs de callback que o Infuse abre ao terminar/falhar. |
| **`lastPlayedUrl`** | Parâmetro retornado no `x-success` do `play`: última URL tocada. |
| **`LSApplicationQueriesSchemes`** | Chave do Info.plist (iOS/tvOS) que lista esquemas que o app pode consultar com `canOpenURL`. Precisa conter `infuse`. |
| **STRM / STRMLNK** | Arquivos de texto (`.strm` = URL HTTP direta tocada pelo Infuse; `.strmlnk` = link a serviço externo com botão "Open"). Alternativa **file-based** ao esquema. |
| **debrid** | Serviço (TorBox/RealDebrid/etc.) que entrega URLs HTTPS pré-autenticadas de arquivos de vídeo cacheados. |

## Fontes canônicas

- **[OFICIAL]** "API for Third-Party Apps & Services" (fonte primária do esquema) —
  https://support.firecore.com/hc/en-us/articles/215090997-API-for-Third-Party-Apps-Services
  (slug legado, mesmo article ID: `.../215090997-Callback-URLs-iOS-only-`)
- **[OFICIAL]** Release notes Infuse (histórico de versões) — https://firecore.com/releases
- **[OFICIAL]** STRM — https://support.firecore.com/hc/en-us/articles/30038115451799-STRM-Files
- **[OFICIAL]** STRMLNK — https://support.firecore.com/hc/en-us/articles/31568155261207-STRMLNK-Files
- **[OFICIAL]** Connection Info (headers fixos Emby/Jellyfin/Plex) — https://support.firecore.com/hc/en-us/articles/21072505575319-Connection-Info-for-Emby-Jellyfin-and-Plex
- **[OFICIAL]** Metadata 101 (naming styles p/ `filename`) — https://support.firecore.com/hc/articles/215090947-Metadata-101
- **[OFICIAL Apple]** `canOpenURL(_:)` — https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)
- **[OFICIAL]** x-callback-url spec — https://x-callback-url.com/specification/
- **[COMUNIDADE]** Threads-chave: limite de protocolo do `url`
  (https://community.firecore.com/t/can-the-argument-in-the-infuse-api-url-be-located-on-a-share/45786),
  deep links tvOS / 8.2.3 (https://community.firecore.com/t/apple-tv-infuse-deep-links/56876),
  API iOS em 7.6.2 (https://community.firecore.com/t/add-x-callback-url-schemes-on-apple-tv/34181),
  custom headers (https://community.firecore.com/t/support-for-custom-headers-to-connect-to-media-server/58481).

## Convenção de confiança

Quando um fato não está na doc oficial verbatim, o arquivo marca **[COMUNIDADE]**,
**[OFICIAL-derivado/implied]** ou **[INFERIDO / a validar]** e cita a fonte da incerteza. Itens "a
validar" (ex.: HLS via esquema, recebimento de callback no tvOS, funcionar no Infuse grátis, formatos
de `sub`) precisam de teste em runtime antes de virarem contrato.
