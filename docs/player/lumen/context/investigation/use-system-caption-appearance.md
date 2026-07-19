## Status

Ausente.

## Evidência

- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:280-286` — estilo de legenda (`textColor`, `textBackgroundColor`, `textFont`, `textFontSize`, `textBold`, `textItalic`, `textPosition`) são `static var` do `SubtitleModel`, com valores fixos definidos em código (ex.: `textColor: Color = .white`), sem qualquer leitura de preferência do sistema.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:349-350` — ao renderizar cada `SubtitlePart`, o `.font` aplicado vem só de `SubtitleModel.textFont` (bold/system font local), nunca de um estilo derivado do SO.
- `rg` em todo `Sources/` por `UIAccessibility`, `MediaAccessibility`, `MACaptionAppearance`, `AXCaption` — nenhuma ocorrência.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:74-75` — únicas flags de legenda existentes são `autoSelectEmbedSubtitle` e `isSeekImageSubtitle`; não há flag do tipo `usesSystemCaptionAppearance` ou equivalente.
- Nenhum arquivo do projeto referencia as APIs da Apple que compõem essa feature no Infuse/tvOS (Settings > Accessibility > Closed Captions, expostas via `MediaAccessibility` framework: `MACaptionAppearanceCopyPreferredCaptionizationStyle`, `MACaptionAppearanceCopyFontDescriptorForStyle`, `MACaptionAppearanceCopyForegroundColor`, etc.) nem observa `MACaptionAppearanceSettingsChangedNotification`.

## O que falta

Não existe nenhum esboço ou hook parcial — a base de estilização (`SubtitleModel` em `KSSubtitle.swift`) já existe e é o ponto correto para plugar a feature, mas hoje ela é 100% estática/hardcoded, sem qualquer ponto de integração com preferências do sistema.

Uma implementação começaria por:
- Importar `MediaAccessibility` e ler as prefs do usuário (`MACaptionAppearanceCopyPreferredCaptionizationStyle`, cor/opacidade de texto e fundo, borda/edge style, fonte) em algum ponto de inicialização do `SubtitleModel` (`Sources/KSPlayer/Subtitle/KSSubtitle.swift`).
- Adicionar uma flag em `KSOptions` (`Sources/KSPlayer/AVPlayer/KSOptions.swift`) tipo `public var usesSystemCaptionAppearance = false` para permitir opt-in/opt-out, seguindo o padrão de flags já existentes ali.
- Substituir os `static var` fixos (`textColor`, `textBackgroundColor`, `textFont`, `textFontSize`, `textBold`, `textItalic`) por lógica que, quando a flag estiver ativa, deriva esses valores das prefs do `MediaAccessibility` em vez de constantes.
- Observar `NSNotification.Name.MACaptionAppearanceSettingsChanged` para atualizar o estilo em tempo real quando o usuário mexe nas configurações do sistema (tvOS: Settings > Accessibility > Subtitles and Captioning), disparando um novo `subtitle(currentTime:)` (linha ~331) para reprocessar `parts` com o estilo atualizado.
- Tratar o path de imagem/legenda embutida (`isImageSubtitle` em `FFmpegAssetTrack.swift`) que não passa por texto estilizável — a feature só se aplica a legendas de texto (SRT/ASS/etc.), não a legendas de imagem (DVB/PGS/DVD).
