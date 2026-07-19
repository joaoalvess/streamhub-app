## Status

parcial

PiP (Picture in Picture) básico existe e funciona (start/stop, mute, restauração de view controller), mas não há nenhuma composição de legenda dentro do PiP: as legendas continuam sendo renderizadas como overlay SwiftUI separado da camada de vídeo entregue ao `AVPictureInPictureController`. Ou seja, PiP funciona, mas sem legenda visível.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift:11-110` — subclasse de `AVPictureInPictureController` com toda a lógica de start/stop/mute/restauração de UI. Não referencia legendas em nenhum ponto.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:42-43` — `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: videoOutput.displayLayer, playbackDelegate: self)`: o content source do PiP no player customizado (decodificação via FFmpeg) é só o `AVSampleBufferDisplayLayer` de vídeo puro.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:572-573` — segundo local onde o mesmo `ContentSource` é recriado, mesma limitação.
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:103` — `KSPictureInPictureController(playerLayer: playerView.playerLayer)` para o backend baseado em `AVPlayer`/`AVPlayerLayer` nativo (sem decode customizado).
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:376-377` — só liga `canStartPictureInPictureAutomaticallyFromInline`, nada sobre legenda.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:88,481` — única flag de configuração relacionada a PiP é `canStartPictureInPictureAutomaticallyFromInline`; não existe nenhuma flag tipo `pipSubtitle` ou equivalente.
- `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:67` — `VideoSubtitleView(model: playerCoordinator.subtitleModel)`: a legenda é uma `View` SwiftUI separada, sobreposta na hierarquia de views, não parte do `CALayer`/buffer de vídeo.
- `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:594-646` — implementação do `VideoSubtitleView`/`subtitleView` (texto ou imagem), confirmando que a renderização de legenda é puramente SwiftUI/UIKit view, desenhada em cima do player, e não incorporada ao pixel buffer.

## Como funciona

O PiP atual cobre apenas o caso "vídeo puro":
1. Para o backend `KSMEPlayer` (decodificação própria via FFmpeg), o app cria um `AVPictureInPictureController.ContentSource` a partir do `AVSampleBufferDisplayLayer` que recebe os frames decodificados de vídeo (sem legenda).
2. Para o backend `KSAVPlayer` (AVFoundation nativo), o PiP usa o `AVPlayerLayer` do próprio `AVPlayer` — nesse caso, se o AVPlayer tiver uma trilha de legenda nativa (`AVMediaSelectionOption`) selecionada via APIs do sistema, o próprio AVFoundation pode compor a legenda no vídeo entregue ao PiP (comportamento do sistema, não implementado pelo KSPlayer). Mas o app usa majoritariamente legendas externas/customizadas (`SubtitleModel`, `KSSubtitle`) renderizadas como view SwiftUI sobreposta, que não é capturada em nenhum dos dois modos de PiP.
3. Toda a lógica em `KSPictureInPictureController` trata apenas de ciclo de vida da picture-in-picture (mostrar/esconder view controller original, mute de áudio, popup da navigation controller) — nenhuma linha compõe texto/imagem de legenda no buffer entregue ao PiP.

## O que falta

Para PiP com legenda funcionar de fato com o pipeline de legenda customizado (`SubtitleModel`/`KSSubtitle`), seria necessário:
- Compor a legenda diretamente nos pixels do `CVPixelBuffer`/`CMSampleBuffer` antes de enviá-lo ao `AVSampleBufferDisplayLayer` usado pelo PiP em `KSMEPlayer.swift:42-43,572-573` (ex.: usando Core Image/Core Graphics ou Metal para desenhar o texto da legenda sobre o frame de vídeo antes de exibir), o que tocaria o pipeline de renderização em `Sources/KSPlayer/Metal/MetalRender.swift` e o ponto onde `videoOutput.displayLayer` recebe amostras (`KSMEPlayer.swift`).
- Alternativamente, usar a API dedicada da Apple `AVPictureInPictureController.ContentSource` com `AVPictureInPictureControllerContentSource` baseado em `activeVideoCallSourceView`/overlay techniques não é aplicável (essa API é para chamadas de vídeo, não vídeo com legenda).
- Para o caminho `KSAVPlayer`, seria preciso garantir que a legenda seja entregue como `AVMediaSelectionOption` real dentro do `AVPlayerItem` (trilha nativa de legenda), e não apenas como overlay SwiftUI, para que o próprio sistema componha a legenda durante o PiP.
- Adicionar uma flag em `KSOptions` (ex.: `isPipSubtitleEnabled`) para controlar esse comportamento e permitir fallback quando a composição não for suportada.
- Tratar performance/sincronização: a composição por frame precisa reusar o timestamp exibido pela legenda (`SubtitleModel`) e ser recalculada a cada frame renderizado, o que é trabalho não trivial e não iniciado em nenhum arquivo do repositório atual.

Nenhum esboço, TODO, comentário ou branch de plataforma relacionado a essa composição foi encontrado no código.
