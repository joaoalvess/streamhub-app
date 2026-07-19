## Status

Ausente (para a feature descrita: janela pequena *dentro do app*, redimensionável/arrastável, tipo mini-player, que permanece sobre a navegação enquanto o usuário continua usando o app). O que existe no repositório é a integração padrão com o **Picture in Picture do sistema** (`AVPictureInPictureController` da AVKit), que é uma feature diferente: o vídeo sai da hierarquia de views do app e vira uma janela flutuante gerenciada pelo SO (fora do processo de UI do app). Não há nenhum componente de mini-player customizado renderizado dentro da própria UI do app.

## Evidência

- `Sources/KSPlayer/AVPlayer/KSPictureInPictureController.swift:11` — subclasse de `AVPictureInPictureController` (API do AVKit/sistema), `@available(tvOS 14.0, *)`. Todo o controle de start/stop delega para `startPictureInPicture()`/`stopPictureInPicture()` (linhas 21, 61), que são APIs do sistema operacional, não um container de view próprio.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:74-90` — propriedade `isPipActive` que, ao ativar, chama `pipController.start(view: self)` (linha 85), delegando inteiramente ao PiP do sistema.
- `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:374-379` — `canStartPictureInPictureAutomaticallyFromInline`, envolto em `#if !os(macOS) && !os(tvOS)`, ou seja, mesmo esse recurso de PiP do sistema é restrito a iOS (não tvOS/macOS) nessa branch de código.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:88` e `:481` — flags `canStartPictureInPictureAutomaticallyFromInline` e `isPipPopViewController`, ambas só regulam comportamento do PiP do sistema (se deve popar o view controller da navegação ao entrar em PiP), não implementam janela in-app.
- `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:506-510` — `pipButton` apenas faz `config.playerLayer?.isPipActive.toggle()`, chamando o mesmo fluxo de PiP do sistema.
- Busca ampla por `floating|miniplayer|mini_player|draggable|resizable window|small window` em todos os `.swift` do repo: **zero ocorrências**. Não há nenhum tipo, view ou controller de "janela pequena in-app".

## O que falta

Uma feature real de "small window in-app, resumível" (ao estilo Infuse) precisaria de componentes que não existem hoje:

1. **Um contêiner de overlay persistente** acima da navegação do app (ex.: um `ZStack`/`UIWindow` extra ou um `OverlayWindow` em nível de `UIWindowScene`) que hospede um `KSPlayerLayer`/`KSVideoPlayerView` reduzido enquanto o restante da UI do app continua interativa por trás — hoje o player só existe como tela cheia dentro da hierarquia normal de navegação (`VideoPlayerView.swift`, `KSVideoPlayerView.swift`).
2. **Estado global de "vídeo em reprodução minimizada"** (ex. um `ObservableObject`/`@Observable` singleton tipo `MiniPlayerCoordinator`) guardando referência ao `KSPlayerLayer`/`KSMEPlayer` atual, posição/tamanho da janela, e o item em reprodução — não existe nenhum coordinator desse tipo; o ciclo de vida do player hoje está atrelado ao view controller que o apresenta (ver `originalViewController`/`viewController` em `KSPictureInPictureController.swift:13-19`, que só existem para restaurar o PiP do sistema, não para gerenciar uma janela in-app independente).
3. **Gestos de arraste/redimensionamento e snap to corner** para a janela pequena — nada equivalente existe; o único controle de UI de PiP é o botão que aciona `AVPictureInPictureController` (`KSVideoPlayerView.swift:506-510`).
4. **Resumo/retomada** já é parcialmente coberto pela infraestrutura de progresso de reprodução do app StreamHub (fora deste pacote Player), mas a integração com uma janela in-app minimizada exigiria que esse estado de progresso continuasse sendo salvo/observado enquanto o player estiver na janela pequena — hoje isso só é exercitado no caminho de tela cheia.

Pontos de partida caso se decida implementar: `Sources/KSPlayer/Core/PlayerView.swift` e `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift` (onde hoje mora o layout de tela cheia e os botões de controle) e `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift` (dono do ciclo de vida do player) seriam os arquivos tocados para extrair um modo de exibição "mini" independente do PiP do sistema.
