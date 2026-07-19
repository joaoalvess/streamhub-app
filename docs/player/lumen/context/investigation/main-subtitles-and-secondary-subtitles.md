# Main subtitles and secondary subtitles

## Status
Ausente

## Evidência
- `README.md:56` — tabela de features GPL vs pago lista explicitamente "Main subtitles and Secondary subtitles" como ✅ pago / ❌ GPL.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:316` — `public var selectedSubtitleInfo: (any SubtitleInfo)?`: modelo de seleção é um único opcional, não uma lista/par.
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift:233` — `open class SubtitleModel: ObservableObject` expõe apenas `selectedSubtitleInfo` e `subtitleDataSouces`/`subtitleInfos`, sem segundo campo de seleção.
- `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:230-231` — auto-seleção de legenda embutida escreve em `subtitleModel.selectedSubtitleInfo` (singular).
- `Sources/KSPlayer/Video/VideoPlayerView.swift:292-293,518-522,589-602` — UI AppKit/UIKit (menu de legendas, toggle) manipula apenas `srtControl.selectedSubtitleInfo`, sempre um único valor.
- `Sources/KSPlayer/SwiftUI/KSVideoPlayerViewBuilder.swift:44-47` e `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:308` — bindings SwiftUI também expõem só `selectedSubtitleInfo`.
- `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift` — decoder de legenda (FFmpeg) processa uma única `assetTrack`/stream por instância; não há conceito de decodificar duas faixas de legenda em paralelo para composição.
- Busca por `secondary`/`second.*subtitle` em todo `Sources/` não retornou nenhuma ocorrência real (apenas falso-positivo de "seconds" em `SubtitleDecode.swift`).

## Como funciona
N/A — não há fluxo, pois a feature não existe no código.

## O que falta
Para uma implementação partiria de:
- `Sources/KSPlayer/Subtitle/KSSubtitle.swift`: `SubtitleModel` precisaria de um segundo slot de seleção (ex.: `secondarySelectedSubtitleInfo`) e lógica para manter duas faixas ativas simultaneamente (hoje `selectedSubtitleInfo` já desativa a anterior via `isEnabled`, o que teria que virar independente por slot).
- `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift` e o pipeline em `Sources/KSPlayer/MEPlayer/` (demuxer/decoder): hoje assume uma única faixa de legenda ativa por vez para decodificação; decodificar duas faixas (possivelmente de fontes diferentes — embutida + externa) exigiria duas instâncias/pipelines de `SubtitleDecode` rodando em paralelo e sincronizadas ao mesmo `KSFrame`/PTS.
- Camada de renderização: `Sources/KSPlayer/Video/VideoPlayerView.swift` e as views SwiftUI (`KSVideoPlayerView.swift`, `KSVideoPlayerViewBuilder.swift`) renderizam um único bloco de texto/imagem de legenda por vez; seria necessário overlay duplo (posicionamento superior/inferior, estilos independentes) para exibir main + secondary simultaneamente.
- UI de seleção (menus em `VideoPlayerView.swift:518` e equivalentes SwiftUI): precisaria de dois seletores/menus distintos em vez de um único "subtitle" toggle.
- Possivelmente `KSOptions` (não encontrado nenhuma flag relacionada em código) para expor uma opção habilitando/desabilitando o segundo trilho.
