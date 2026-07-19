# ProgressBar Preview

## Status
Ausente (dead code parcial, mas não integrado a nada).

## Evidência
- `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:24-132` — classe `ThumbnailController` completa e funcional: decodifica N frames (`thumbnailCount`, default 100) via FFmpeg (`av_seek_frame` + `avcodec_send_packet`/`avcodec_receive_frame`) e gera `[FFThumbnail]` (imagem + timestamp) através de `ThumbnailControllerDelegate.didUpdate(thumbnails:forFile:withProgress:)`.
- `/opt/homebrew/bin/rg -n "ThumbnailController|FFThumbnail|generateThumbnail"` em todo o repo Swift retorna apenas ocorrências dentro do próprio arquivo — nenhuma outra classe instancia `ThumbnailController`, implementa o delegate ou chama `generateThumbnail`. É código morto/isolado.
- `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:96` — `func thumbnailImageAtCurrentTime() async -> CGImage?` (protocolo `MediaPlayerProtocol`).
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:388-393,580` — implementação via `AVURLAsset.thumbnailImage(currentTime:)`, gera **um único** frame no tempo atual (`playerItem.currentTime()`), não um frame arbitrário para preview de scrub.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:438` — mesma assinatura implementada no player FFmpeg.
- `Sources/KSPlayer/Video/IOSVideoPlayerView.swift:232-241` — único chamador de `thumbnailImageAtCurrentTime()`: dentro de `override open func change(definitionIndex:)`, usado só para mostrar uma imagem de "mask" ao trocar de qualidade/definição (cobre a tela com o último frame enquanto troca a fonte). Não tem relação com arrastar a progress bar.
- `Sources/KSPlayer/Core/UIKitExtend.swift:10-95` (`KSSlider`/`UXSlider`) e `Sources/KSPlayer/Core/PlayerToolBar.swift:22-269` — o slider de progresso (`timeSlider`) só expõe `touchDown`/`valueChanged`/`touchUpInside` e atualiza o tempo textual; não há hook de preview de thumbnail durante o arrasto, nem view de popup/tooltip de imagem.
- `Sources/KSPlayer/Video/VideoPlayerView.swift` e `MacVideoPlayerView.swift` — mesma coisa: manipulam `toolBar.timeSlider` para seek, sem nenhuma preview visual de frame.

## O que falta (por onde uma implementação começaria)
1. **Conectar o gerador ao player**: `ThumbnailController` já resolve a parte pesada (decodificar frames via FFmpeg), mas roda como uma varredura completa e assíncrona do arquivo inteiro (100 thumbnails pré-gerados), não como "pegue-me o frame perto do tempo X sob demanda enquanto arrasto o slider" — precisaria de um modo de busca pontual (parecido com o que `thumbnailImageAtCurrentTime` já faz no AVPlayer/KSMEPlayer, mas parametrizado por tempo arbitrário, não só o tempo atual).
2. **UI de preview**: `KSSlider`/`UXSlider` (`Sources/KSPlayer/Core/UIKitExtend.swift`) precisaria de um evento de "arrasto em progresso" (hoje só dispara `valueChanged`/`touchUpInside`) e uma view flutuante (popup com `UIImageView` + label de tempo) posicionada acima do thumb, atualizada a cada mudança de valor durante o arrasto.
3. **Cache de thumbnails**: para não decodificar frame por frame a cada pixel de arrasto, seria necessário pré-gerar e cachear os N thumbnails de `ThumbnailController` no início da reprodução (ele já devolve incrementalmente via delegate) e mapear `progress → thumbnail mais próximo`.
4. **Integração tvOS**: `PlayerToolBar`/`VideoPlayerView` não têm variante de foco/hover para tvOS que dispare preview ao navegar o slider com o remote — teria que ser adicionado especificamente para o remote da Apple TV (sem touch/drag).
5. Nenhuma flag em `KSOptions` existe para habilitar/desabilitar essa feature (`/opt/homebrew/bin/rg -i "thumbnail|preview" Sources/KSPlayer/Core/KSOptions.swift` não retorna nada), então também faltaria a opção de configuração pública.

Em resumo: existe a peça de decodificação de frames (FFmpeg) pronta e correta em `ThumbnailController`, mas ela está desconectada — nunca é chamada — e não existe nenhum caminho de UI (slider → preview popup) nem estado de cache que ligue thumbnails ao arrasto da progress bar.
