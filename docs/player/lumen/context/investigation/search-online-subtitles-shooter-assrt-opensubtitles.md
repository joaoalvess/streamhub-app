# Search online subtitles (shooter/assrt/opensubtitles)

## Status
Presente.

## Evidência
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:63-77` — protocolos `SubtitleDataSouce`, `FileURLSubtitleDataSouce`, `CacheSubtitleDataSouce`, `SearchSubtitleDataSouce` que definem os dois modos de busca (por `fileURL`/hash e por `query`/idiomas).
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:161-194` — `ShooterSubtitleDataSouce`: calcula hash do arquivo (`URL.shooterFilehash`, linhas 375-403) e faz POST em `https://www.shooter.cn/api/subapi.php`, parseando `Files`/`Link`/`Delay`.
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:196-264` — `AssrtSubtitleDataSouce`: busca por `query` em `https://api.assrt.net/v1/sub/search` com token Bearer, depois resolve detalhes/URLs de download em `loadDetails(assrtSubID:)` (`https://api.assrt.net/v1/sub/detail`).
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:266-356` — `OpenSubtitleDataSouce`: busca por `query`/`imdbID`/`tmdbID`/`languages` em `https://api.opensubtitles.com/api/v1/subtitles` com `Api-Key`, resolve link de download em `loadDetails(fileID:)` via `.../v1/download`.
- `Sources/KSPlayer/Subtitle/SubtitleDataSouce.swift:79-81` — `KSOptions.subtitleDataSouces` (ponto de configuração/injeção de fontes; default só tem `DirectorySubtitleDataSouce()`, os provedores online não vêm habilitados por padrão).
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:291,304-305,360-370` — `SubtitleModel` consome `KSOptions.subtitleDataSouces`: no `didSet` de `url` chama `addSubtitle(dataSouce:)` para cada fonte (busca por arquivo) e expõe `searchSubtitle(query:languages:)` que itera as fontes que são `SearchSubtitleDataSouce` e populam `subtitleInfos` (usado pela UI para listar/selecionar legenda).
- `Demo/SwiftUI/Shared/TracyApp.swift:199` — uso real de ponta a ponta: `KSOptions.subtitleDataSouces = [DirectorySubtitleDataSouce(), ShooterSubtitleDataSouce(), AssrtSubtitleDataSouce(token: "..."), OpenSubtitleDataSouce(apiKey: "...")]`.

## Como funciona
1. `KSOptions.subtitleDataSouces` é uma lista estática configurável de fontes de legenda (arquivo local, Shooter, Assrt, OpenSubtitles, cache em plist).
2. Quando `SubtitleModel.url` é setado (novo vídeo carregado), cada `SubtitleDataSouce` é consultada via `addSubtitle(dataSouce:)`, que chama `searchSubtitle(fileURL:)` nas fontes que implementam `FileURLSubtitleDataSouce` — isso inclui `ShooterSubtitleDataSouce`, que calcula o hash do arquivo (4 blocos de 4KB via `FileHandle`) e consulta a API do Shooter.
3. Separadamente, `SubtitleModel.searchSubtitle(query:languages:)` é o ponto de entrada para busca textual (chamado com `nil` automaticamente ao trocar de vídeo, e presumivelmente com texto real por alguma UI de busca) — itera as fontes `SearchSubtitleDataSouce` (Assrt, OpenSubtitles) e roda cada uma em `Task { @MainActor in ... }`, atualizando `subtitleInfos`.
4. Cada resultado vira um `URLSubtitleInfo` (subclasse de `KSSubtitle` que implementa `SubtitleInfo`), que faz download/parse do arquivo de legenda sob demanda quando `isEnabled` é setado (`SubtitleDataSouce.swift:20-28`).
5. Há cache local em plist (`PlistCacheSubtitleDataSouce`) que registra `downloadURL` associada ao `fileURL` do vídeo, evitando nova busca online em execuções futuras.
6. Todo o fluxo é exercitado de ponta a ponta no app de demonstração (`TracyApp.swift:199`), que registra as quatro fontes (diretório local + as três integrações online) com credenciais de exemplo.

## O que falta
N/A — feature presente e funcional no fork. Observação (não é lacuna de implementação, é config): por padrão o app real (fora da demo) precisaria explicitamente atribuir `KSOptions.subtitleDataSouces` incluindo `ShooterSubtitleDataSouce()`, `AssrtSubtitleDataSouce(token:)` e/ou `OpenSubtitleDataSouce(apiKey:)` (com credenciais próprias) para habilitar a busca online, já que o default de biblioteca só ativa `DirectorySubtitleDataSouce`.
