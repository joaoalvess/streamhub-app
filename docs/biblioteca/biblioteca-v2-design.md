# Biblioteca v2 — busca, badges e grade completa

Spec aprovada em 2026-07-22. Escopo: somente o app. A reorganização do servidor Jellyfin é uma entrega separada (guia ao final desta frente).

## Problema

A aba Biblioteca hoje só oferece fileiras horizontais com teto de 50 itens por view. Com ~1.240 vídeos no servidor, a maior parte do acervo é inalcançável e não existe busca. Além disso o card não diz nada sobre o arquivo: não dá para saber se é 4K ou 1080p, dublado ou legendado, sem dar play.

## Estado real do servidor (medido em 2026-07-22)

- 4 views, todas `CollectionType=none` (pastas genéricas por armazenamento): Nuvem GDrive, Nuvem Mega.nz, Torbox Preservados, Torbox Webdav.
- Contagem por tipo: `Movie: 1055`, `Episode: 159`, `Season: 43`, `Series: 25`, `Folder: 333`, `Video: 1`. Episódios de série em geral vêm como `Movie` com nome de arquivo cru (`Elementary.S05E06`, `FERIASEXDIRETORIA2x03`) — sem bibliotecas tipadas o Jellyfin não roda identificação/scraping.
- `MediaStreams` está disponível via `fields=MediaStreams`: traz `Height` do vídeo e `Language` das faixas de áudio/legenda por arquivo. É a fonte dos badges — dado real, não parsing de nome.
- `searchTerm` funciona no `GET /Items` (busca por substring no nome, `recursive=true`).
- Há duplicatas entre views (mesmo título no GDrive e no Torbox).

## Escopo

Entra:

1. Cabeçalho de ações na aba (Buscar + Todos os títulos).
2. Busca server-side em tela cheia.
3. Badges de resolução e áudio nos cards + título com 2 linhas no foco.
4. Grade paginada "Todos os títulos" em ordem alfabética.
5. Dedupe da fileira "Adicionados recentemente" por nome+ano.

Fora (dependem do servidor arrumado): separação filmes/séries, hierarquia temporada/episódio, sinopse/gêneros, merge real de duplicatas.

## Design

### Cabeçalho de ações

Acima das fileiras, um `HStack` em `focusSection` com dois botões-pílula: **Buscar** (ícone `magnifyingglass`) e **Todos os títulos** (ícone `square.grid.3x3`). Cada um abre um `fullScreenCover` próprio. Padding horizontal `Theme.Metrics.edgeH`, mesmo vocabulário visual do app.

### Busca (`LibrarySearchView` + `LibrarySearchViewModel`)

- Mesmo padrão da `SearchView` global: `.searchable` + `task(id:)` com debounce de 300 ms e query mínima de 2 caracteres.
- Endpoint: `GET /Items?userId&searchTerm=<q>&recursive=true&mediaTypes=Video&sortBy=SortName&sortOrder=Ascending&limit=60&fields=MediaStreams`.
- Resultados em `LazyVGrid` de `LibraryCardView` (com badges). Selecionar toca direto, com o mesmo fluxo de play + reporter de hoje.
- Estados: idle (dica de uso), loading, resultados, vazio, falha com "Tentar novamente" — mesmos vocabulários da SearchView.

### Badges nos cards

`JellyfinItem` ganha `mediaStreams` e `LibraryEntry` deriva dois rótulos no `init`:

- `resolutionLabel` a partir do maior `Height` entre streams de vídeo: `>= 2000 → "4K"`, `>= 1000 → "1080p"`, `>= 690 → "720p"`, `> 0 → "SD"`, sem stream → sem badge.
- `audioLabel` a partir dos idiomas (`por` e variantes `pob`/`pt`, prefixo case-insensitive):
  - áudio pt **e** áudio em outro idioma → `DUAL`
  - só áudio pt → `DUB`
  - sem áudio pt, mas legenda pt → `LEG`
  - nada em pt → sem badge
- UI: cápsulas pequenas sempre visíveis no canto superior esquerdo do pôster (texto branco, fundo preto translúcido), na ordem resolução → áudio. Sem `MediaStreams` no payload, o card fica como hoje.
- Título no foco passa de `lineLimit(1)` para `lineLimit(2)`.

### Grade "Todos os títulos" (`LibraryAllView` + `LibraryAllViewModel`)

- `fullScreenCover` com `LazyVGrid` de todos os vídeos, A–Z.
- Endpoint paginado: `GET /Items?userId&recursive=true&mediaTypes=Video&sortBy=SortName&sortOrder=Ascending&startIndex=<n>&limit=100&fields=MediaStreams`.
- `JellyfinQueryResult` passa a decodificar `TotalRecordCount`; o modelo acumula páginas e dispara a próxima quando um card do último terço aparece. Para quando `entries.count >= total`.
- Falha na primeira página → tela de erro com retry; falha em página seguinte → botão "Carregar mais" no rodapé.
- Cards com badges, play direto.

### Fluxo de play compartilhado

O trio play/stop/reporter que hoje vive na `LibraryView` (`play(_:)`, `closePlayer()`, `activeSessionID`, `reporter`, binding do cover) é extraído para `LibraryPlaybackModel` (`@Observable @MainActor`), instanciado por cada uma das três telas (aba, busca, grade). Cada tela mantém seu próprio `fullScreenCover` de `NativePlayerView`. O refresh do resume após fechar o player continua responsabilidade da aba (as outras telas apenas notificam via closure opcional `onSessionEnded`).

### Dedupe de "Adicionados recentemente"

Função pura `LibraryViewModel.dedupedByTitle(_:)`: chave = nome lowercased com fold de diacríticos + ano (quando houver); mantém a primeira ocorrência (a lista já vem por `DateCreated` desc). Aplicada só nessa fileira.

## Mudanças por arquivo

| Arquivo | Mudança |
|---|---|
| `StreamHub/Library/JellyfinModels.swift` | `JellyfinMediaStream` (Type, Height, Language); `JellyfinItem.mediaStreams`; `JellyfinQueryResult.totalRecordCount` |
| `StreamHub/Library/JellyfinAPI.swift` | `fields=MediaStreams` nas queries de itens; novos `search(term:limit:)` e `allItems(startIndex:limit:)` |
| `StreamHub/Library/LibraryViewModel.swift` | `LibraryEntry.resolutionLabel`/`audioLabel`; `dedupedByTitle`; aplica dedupe no latest |
| `StreamHub/Library/LibraryRowView.swift` | badges no `LibraryCardLabel`; título com 2 linhas no foco |
| `StreamHub/Library/LibraryPlaybackModel.swift` (novo) | fluxo play/stop/reporter extraído da `LibraryView` |
| `StreamHub/Library/LibrarySearchView.swift` (novo) | tela de busca + view model |
| `StreamHub/Library/LibraryAllView.swift` (novo) | grade paginada + view model |
| `StreamHub/Library/LibraryView.swift` | cabeçalho de ações, covers de busca/grade, adota `LibraryPlaybackModel` |

Arquivos novos entram no target automaticamente (pastas sincronizadas do Xcode) — não tocar no `project.pbxproj`.

## Restrições de código

- Tipos de dados/parsing novos são `nonisolated` (o projeto usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- Sem force-unwrap (hook bloqueia), sem comentários, diffs mínimos.

## Testes (Swift Testing, fixtures inline, sem rede)

- `LibraryMappingTests`: derivação de badges (4K DUAL, 1080p DUB, LEG por legenda, sem streams → sem badges), dedupe por nome+ano com e sem diacríticos.
- `JellyfinRequestTests`: query de busca (searchTerm, fields, sort) e de paginação (startIndex/limit) montadas corretamente.
- Paginação do `LibraryAllViewModel`: acumula páginas, para no total, marca falha de página intermediária.

## Depois desta frente

Guia de reorganização do servidor (bibliotecas tipadas Filmes/Séries com TMDb, nomenclatura, o que cada mount rclone permite, e o risco de perda de posição de playback ao recriar bibliotecas — os IDs de item mudam).
