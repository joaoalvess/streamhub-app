## Status

Presente.

## Evidência

- Sources/KSPlayer/AVPlayer/KSOptions.swift:28 — `public var isLoopPlay = KSOptions.isLoopPlay` (propriedade de instância, valor default por classe em `KSOptions.swift:472`).
- Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:17 — `private var loopCount = 1`.
- Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:224-236 — `sourceDidFinished()`: se `options.isLoopPlay`, incrementa `loopCount`, notifica o delegate (`playBack(player:loopCount:)`) e reinicia `audioOutput.play()` / `videoOutput?.play()` sem finalizar a reprodução.
- Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:355-367 — `seek(time:completion:)`: quando `time >= duration && options.isLoopPlay`, faz seek para `0` em vez de deixar o tempo estourar, sustentando o loop no path de seek/EOF.
- Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:410 — reset de `loopCount = 0` (ex.: ao trocar de mídia).
- Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:83 — `private var playerLooper: AVPlayerLooper?` (backend AVFoundation).
- Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:90-91 — `loopCountObservation` / `loopStatusObservation` (`NSKeyValueObservation`).
- Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:229 — `if !options.isLoopPlay` controla comportamento de fim de item quando loop está desligado.
- Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:302-319 — quando `options.isLoopPlay`, invalida observers antigos, chama `playerLooper?.disableLooping()`, cria `AVPlayerLooper(player:templateItem:)` (API nativa da Apple para loop sem gap) e observa `\.loopCount` e `\.status` via KVO, propagando erro se `status == .failed`.
- Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:113 — `func playBack(player: some MediaPlayerProtocol, loopCount: Int)` no protocolo de delegate, comum aos dois backends.
- Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:72 — `public var loopCount: Int = 0` espelhado na camada de UI.
- Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:440-442 — `playBack(player:loopCount:)` atualiza `self.loopCount`.
- Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:597 — `self.options.isLoopPlay = event.repeatType != .off`, ligando o loop ao remote control / Now Playing Info (repeat mode do sistema).
- Demo/SwiftUI/Shared/Defaults.swift:50-53,192 — `@AppStorage("isLoopPlay")` persiste a preferência e sincroniza com `KSOptions.isLoopPlay`.
- Demo/SwiftUI/Shared/SettingView.swift:163-191 — `Toggle("Loop Play", isOn: $isLoopPlay)` expõe o recurso na tela de configurações do app de demonstração.

## Como funciona

Existem dois caminhos independentes e completos, um por backend de player:

1. **Backend FFmpeg (`KSMEPlayer`)**: ao atingir o fim do arquivo, `MEPlayerItem`/fonte de dados chama `sourceDidFinished()` no player. Se `options.isLoopPlay` estiver ativo, em vez de marcar `playbackState = .finished`, o player incrementa `loopCount`, notifica o delegate e simplesmente manda `audioOutput`/`videoOutput` tocarem de novo — presumindo que o pipeline de decodificação (que já processa o arquivo em loop/circularmente via buffers) recomeça a entregar frames desde o início. O tratamento de `seek(time:)` reforça isso: se o app pedir um seek além da duração com loop ligado, o tempo de destino é grampeado em `0`.

2. **Backend AVFoundation (`KSAVPlayer`)**: usa a API nativa da Apple `AVPlayerLooper`, que empilha múltiplos `AVPlayerItem` clonados a partir do item template no `AVQueuePlayer` interno, garantindo loop "seamless" (sem gap perceptível) — é a mesma técnica recomendada pela Apple para looping sem cortes. O código observa `loopCount` e `status` via KVO para propagar eventos e erros ao delegate comum (`playBack(player:loopCount:)`), unificando a experiência com o backend FFmpeg do ponto de vista do chamador.

Em ambos os casos, a flag pública `KSOptions.isLoopPlay` (com default estático configurável) é o único ponto de configuração exposto ao app cliente, e o app de demonstração (SwiftUI) já tem UI (`Toggle`) e persistência (`@AppStorage`) prontas para essa opção. Há também integração com o remote control do sistema (`KSPlayerLayer.swift:597`), que liga o modo repeat do Now Playing/Control Center diretamente a `isLoopPlay`.

## O que falta

Nada de essencial — a feature está implementada de ponta a ponta nos dois backends, com propagação de eventos (loopCount) e integração de UI/remote. Não foram encontrados TODOs, stubs ou branches de plataforma desabilitando o recurso (tvOS/iOS/macOS todos compartilham o mesmo código, sem `#if os(...)` em torno da lógica de loop).
