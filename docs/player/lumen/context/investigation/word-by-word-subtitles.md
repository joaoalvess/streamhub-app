# Word-by-word subtitles

## Status
Ausente.

## Evidência
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:14-35` — `SubtitlePart` só guarda um único par `start`/`end` (TimeInterval) por bloco de legenda e um `NSAttributedString` de texto inteiro; não há estrutura para timing por palavra/token.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:236-256` — `SubtitleModel.subtitle(currentTime:)` busca e exibe o `SubtitlePart` inteiro correspondente ao tempo atual; a granularidade de exibição é a linha completa, sem subdivisão temporal interna.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:154-166` — `KSSubtitle.search(for:)` faz a busca por bloco (`part == time`), reforçando que a menor unidade endereçável é o bloco de legenda, não a palavra.
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:38-131` — `AssParse.parsePart` lê a tag ASS `Dialogue` e processa apenas os overrides de estilo (`{\an, \b, \c, \fn, \fs, \i, \shad, \u, \1c..\4c}`) via `parseStyle`; a tag de karaokê ASS `\k`/`\K`/`\kf` (que carrega os timings por sílaba/palavra em centésimos de segundo) não aparece em nenhum lugar do `switch` de `parseStyle` (`Sources/KSPlayer/Subtitle/KSParseProtocol.swift:189-233`) — é silenciosamente ignorada como qualquer caractere não mapeado (`default: break`, linha ~230).
- `Sources/KSPlayer/Subtitle/KSParseProtocol.swift:133-263` (`SrtParse`, `VTTParse`) — nenhum parsing de tags de cue WebVTT com timestamp por palavra (`<00:00:01.500>palavra`), que é o mecanismo padrão do WebVTT para destacar palavra a palavra; o parser de VTT só extrai o par de timestamps do cue inteiro e o texto bruto.
- `rg -in "\\k|karaoke|perWord|wordTiming|highlight"` em todo `Sources/` não retornou nenhuma ocorrência relacionada a legendas — os únicos hits de "highlighted" são de UI de foco de botões (`PlayerToolBar.swift`, `AppKitExtend.swift`), sem relação com subtítulos.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:74-75` — únicas flags relacionadas a legenda são `autoSelectEmbedSubtitle` e `isSeekImageSubtitle`; nenhuma flag de granularidade/destaque por palavra.

## O que falta
Uma implementação do zero precisaria de, no mínimo:
1. **Modelo de dados**: estender `SubtitlePart` (`Sources/KSPlayer/Subtitle/KSSubtitle.swift:14`) para carregar uma lista opcional de sub-segmentos com timing próprio (ex.: `[(range: NSRange, start: TimeInterval, end: TimeInterval)]`), em vez de um único `start`/`end` por bloco.
2. **Parsing**:
   - Em `AssParse.parsePart`/`parseStyle` (`KSParseProtocol.swift`), interpretar as tags de karaokê `\k`, `\K`, `\kf`, `\ko` dentro de `splitStyle()`/`parseStyle()`, acumulando o deslocamento temporal por trecho de texto.
   - Em `VTTParse.parsePart`, interpretar timestamps de cue inline (`<hh:mm:ss.mmm>`) que o WebVTT usa para karaokê/word-highlight.
   - `SrtParse` não tem mecanismo nativo para isso no formato SRT puro (SRT não suporta timing por palavra), então ficaria fora de escopo para esse parser.
3. **Renderização em tempo real**: em `SubtitleModel.subtitle(currentTime:)` (`KSSubtitle.swift:236`), ao invés de aplicar apenas `[.font: SubtitleModel.textFont]` ao texto inteiro, seria necessário recalcular a cada tick quais sub-trechos já foram "ditos" (com base no offset acumulado dos tokens) e aplicar um atributo de destaque (cor/negrito) incremental sobre o `NSMutableAttributedString`, análogo ao que players comerciais (Infuse, Plex) fazem para karaokê.
4. **Hooks de UI**: os locais que renderizam `part.text` (`KSVideoPlayerViewBuilder.swift`, `VideoPlayerView.swift`) tratariam o `NSAttributedString` já pronto, então não precisariam de mudança estrutural além de já refletir o `NSMutableAttributedString` atualizado por tick.

Nenhum desses pontos existe hoje mesmo em forma de esboço — não há campos de dados, parsing de tags de karaokê, nem lógica de destaque incremental em nenhum arquivo do módulo `Subtitle` ou `MEPlayer`.
