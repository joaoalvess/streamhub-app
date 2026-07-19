## Status

Presente.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift:11` — `class KSPictureInPictureController: AVPictureInPictureController`, com `start(view:)` e `stop(restoreUserInterface:)` completos, tratando popup de `UIViewController`/`UINavigationController` e mute.
- `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:101-112` — `_pipController` lazy criando `KSPictureInPictureController(playerLayer:)` para o backend AVPlayer.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:40-52` — `_pipController` lazy criando `KSPictureInPictureController(contentSource:)` via `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)` para o backend FFmpeg (decode via `AVSampleBufferDisplayLayer`).
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:475-497` — `extension KSMEPlayer: AVPictureInPictureSampleBufferPlaybackDelegate`, implementando `setPlaying`, `timeRangeForPlayback`, `isPlaybackPaused`, `didTransitionToRenderSize`, `skipByInterval`, `shouldProhibitBackgroundAudioPlayback`.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:393,401` — `pipController?.invalidatePlaybackState()` chamado em mudanças de estado de playback.
- `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:572-573` — recriação do `contentSource`/`_pipController` quando o `displayLayer` muda.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:74-90` — propriedade `isPipActive` que chama `pipController.start(view:)`/`stop(restoreUserInterface:)`.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:475-481` — `extension KSPlayerLayer: AVPictureInPictureControllerDelegate`, tratando `didStopPictureInPicture` e `restoreUserInterfaceForPictureInPictureStopWithCompletionHandler`.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:376-377` — `options.canStartPictureInPictureAutomaticallyFromInline` propagado ao `pipController`.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:651` — checagem de `player.pipController?.isPictureInPictureActive` (guardada por `@available(tvOS 14.0, *)`).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:88,481` — flag `canStartPictureInPictureAutomaticallyFromInline` (default `true`) exposta em `KSOptions`.
- `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:88` — `var pipController: KSPictureInPictureController? { get }` no protocolo comum a todos os players.
- `Sources/KSPlayer/Core/PlayerToolBar.swift:160,179` — botão de PiP na toolbar (`pipButton`), escondido quando `!AVPictureInPictureController.isPictureInPictureSupported()`.
- `Sources/KSPlayer/Core/PlayerView.swift:25` — `case pictureInPicture` no enum `PlayerButtonType`.
- `Sources/KSPlayer/Video/VideoPlayerView.swift:144,155-157` — binding do botão de toolbar a `playerLayer?.isPipActive`, toggle no tap.
- `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:508` — `config.playerLayer?.isPipActive.toggle()` na camada SwiftUI.

## Como funciona

Existem dois caminhos de PiP, um para cada backend de player, ambos concentrados na classe `KSPictureInPictureController` (subclasse de `AVPictureInPictureController`, `@available(tvOS 14.0, *)`):

1. **Backend `KSAVPlayer` (AVPlayer nativo)**: usa o inicializador clássico `AVPictureInPictureController(playerLayer:)`, apropriado quando o player renderiza via `AVPlayerLayer`.
2. **Backend `KSMEPlayer` (decode via FFmpeg)**: usa o inicializador moderno baseado em `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`, com `KSMEPlayer` implementando `AVPictureInPictureSampleBufferPlaybackDelegate` para informar play/pause, range de tempo, seek (`skipByInterval`) e política de áudio em background ao sistema. Isso é necessário porque o pipeline FFmpeg não usa `AVPlayerLayer`, e sim `AVSampleBufferDisplayLayer`, exigindo o contrato "sample buffer" de PiP do AVKit.

O `KSPlayerLayer` expõe `isPipActive: Bool` como a chave para ligar/desligar o PiP a partir da UI (toolbar/SwiftUI). Ao ativar, `KSPictureInPictureController.start(view:)` guarda o `UIViewController`/`UINavigationController` de origem, opcionalmente faz pop/dismiss dele (comportamento controlado pela flag `KSOptions.isPipPopViewController`) e ativa o PiP nativo (`startPictureInPicture()`). Ao encerrar, `stop(restoreUserInterface:)` restaura a hierarquia de view controllers salva e retoma o play com áudio.

O delegate `AVPictureInPictureControllerDelegate` é implementado em `KSPlayerLayer`, tratando o encerramento do PiP pelo usuário (botão nativo do sistema) e a restauração de interface.

A flag `KSOptions.canStartPictureInPictureAutomaticallyFromInline` (default `true`) é propagada para o `AVPictureInPictureController` nativo, habilitando início automático de PiP ao sair do app (padrão do AVKit em iOS; documentado como propriedade herdada de `AVPictureInPictureController`).

O botão de PiP na toolbar (`PlayerButtonType.pictureInPicture`) só aparece quando `AVPictureInPictureController.isPictureInPictureSupported()` retorna true, e a UI SwiftUI (`KSVideoPlayerView`) também tem um toggle equivalente.

## O que falta

Não se aplica — feature completa (ponta a ponta) para ambos os backends de decode, com integração de toolbar e SwiftUI. Nenhuma lacuna identificada no fluxo de código; validação real em dispositivo/tvOS fica a cargo do dono do projeto (não executada nesta investigação).
