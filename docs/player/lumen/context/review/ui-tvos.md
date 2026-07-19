# Auditoria de UI tvOS — KSPlayer (fork StreamHub)

Escopo: `Sources/` do fork GPL do KSPlayer. Foco: foco (focus engine) do tvOS, gestos que
não existem/funcionam mal em tvOS, layout quebrado, estados de loading/erro mal
tratados, controles que não refletem o estado real do player.

O consumidor tvOS confirmado é o player SwiftUI multiplataforma
(`Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift` + `KSVideoPlayer.Coordinator` em
`Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift` + `Sources/KSPlayer/SwiftUI/Slider.swift`):
é o que `Demo/SwiftUI/Shared/ContentView.swift` e `TracyApp.swift` instanciam para todas
as plataformas, incluindo tvOS (`Demo/demo-tvOS` não tem fontes próprias — reusa o
target multiplataforma). A pilha antiga baseada em UIKit
(`Sources/KSPlayer/Video/VideoPlayerView.swift` etc.) também compila para tvOS
(`canImport(UIKit)`, sem exclusão de `os(tvOS)`), mas não há nenhum consumidor tvOS dela
no repo — por isso os findings abaixo focam na pilha SwiftUI, que é a que efetivamente
roda no controle remoto da Apple TV.

Cada finding foi confirmado lendo o código (arquivo/linha citados); quando o
comportamento depende de como o foco/remoto do tvOS interpreta eventos, isso está
indicado explicitamente.

---

## 1. [ALTA] "Pin" dos controles (seta para cima) é desfeito silenciosamente por qualquer soluço de buffer

**Arquivos:**
`Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:196-210` (gesto) e
`Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:187-216` (`mask(show:autoHide:)`) e
`:221-256` (`player(layer:state:)`)

No controle remoto da Apple TV, pressionar **para cima** enquanto o foco está no vídeo
(`focusableField == .play`) chama:

```swift
case .up:
    playerCoordinator.mask(show: true, autoHide: false)
```

A intenção explícita de `autoHide: false` é manter os controles visíveis até o usuário
decidir escondê-los (não authohide depois de `KSOptions.animateDelayTimeInterval`).
`mask(show:)` de fato respeita isso — só agenda o `DispatchWorkItem` de auto-hide
`if autoHide` (`KSVideoPlayer.swift:192-202`).

O problema é que esse "pin" só existe como um argumento passado nessa única chamada —
não há nenhum estado persistente tipo `isPinned`. Qualquer transição de estado do
player, reportada pelo delegate `player(layer:state:)`, **sobrescreve `isMaskShow`
incondicionalmente**:

```swift
public func player(layer: KSPlayerLayer, state: KSPlayerState) {
    onStateChanged?(layer, state)
    if state == .readyToPlay {
        ...
    } else if state == .bufferFinished {
        isMaskShow = false          // <-- ignora se o usuário pediu para fixar os controles
    } else {
        isMaskShow = true
        ...
    }
}
```

**Cenário concreto de falha:** o usuário está assistindo um stream de rede (o caso
normal do StreamHub — vídeo remoto, não arquivo local), pressiona ↑ para fixar a barra
de controles e navegar (ver track de áudio, legendas, velocidade). Bastando o player
soltar um "soluço" de rede — uma transição `buffering → bufferFinished`, algo rotineiro
em streaming e que o próprio `KSPlayerLayer` trata como caso comum
(`KSPlayerLayer.swift:180-183`, um fallback que roda a cada 0.1s enquanto o timer está
ativo, e `:425-433`, chamado a cada atualização de `loadState`) — o delegate dispara
`state == .bufferFinished` e zera `isMaskShow` na hora, fechando a barra que o usuário
tinha acabado de pedir para ficar aberta, no meio da navegação. Do ponto de vista do
usuário, os controles "somem sozinhos" sem qualquer gesto ou timeout visível.

**Correção sugerida:** manter um flag (`isPinned`) no `Coordinator` setado por
`mask(show:autoHide: false)` e checado em `player(layer:state:)` antes de forçar
`isMaskShow = false`; ou não deixar o delegate de estado escrever diretamente em
`isMaskShow`, e sim rotear tudo por `mask(show:autoHide:)`.

---

## 2. [ALTA] Cancelamento do gesto de arrastar na barra de progresso do tvOS deixa o player pausado e o tempo sem sincronizar

**Arquivos:** `Sources/KSPlayer/SwiftUI/Slider.swift:140-169` (`TVSlide.actionPanGesture`)
cruzado com `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:561-586`
(`VideoTimeShowView.body`)

A barra de progresso usada no tvOS é a struct `Slider` deste mesmo módulo
(`Slider.swift:14-30`, compilada só `#if os(tvOS)`), que sombreia `SwiftUI.Slider` dentro
do pacote — logo `VideoTimeShowView` (usada tanto no rodapé do tvOS quanto, via
`ornamentControlsView`, no xrOS) acaba usando essa implementação customizada baseada em
`UIPanGestureRecognizer` + `UIControl`.

```swift
switch sender.state {
case .began, .possible: ...
case .changed:
    ...
    value.wrappedValue = wrappedValue
    onEditingChanged(true)
case .ended:
    delayItem = DispatchWorkItem { ... onEditingChanged(false) ... }
    DispatchQueue.main.asyncAfter(...)
case .cancelled, .failed:
//            value.wrappedValue = beganValue
    break
```

`onEditingChanged(true)` (chamado durante `.changed`) manda o `Coordinator` **pausar** o
player:

```swift
// KSVideoPlayerView.swift:569-575
Slider(..., in: 0 ... Float(model.totalTime)) { onEditingChanged in
    if onEditingChanged {
        config.playerLayer?.pause()
    } else {
        config.seek(time: TimeInterval(model.currentTime))
    }
}
```

Mas se o `UIPanGestureRecognizer` transicionar para `.cancelled` ou `.failed` — o que
acontece sempre que o gesto é interrompido pelo sistema (outro gesture recognizer ganha
prioridade, o app perde o primeiro-respondedor, etc.) — o `break` não faz **nada**: não
chama `onEditingChanged(false)`, não restaura `beganValue` (a linha que faria isso está
comentada). Resultado: o player fica pausado (do `pause()` chamado em `.changed`) e
nunca recebe o `seek(time:)` que reativaria a reprodução — nada no código devolve o
player ao estado de "tocando".

**Cenário concreto de falha:** usuário foca a barra de progresso no tvOS e começa a
arrastar; o gesto é cancelado no meio (comum quando o SwiftUI/UIKit interrompe o pan por
qualquer motivo do sistema). O vídeo trava pausado sem nenhum feedback de que algo deu
errado — o usuário precisa descobrir sozinho que precisa apertar o botão de play de
novo. Além disso, como `config.seek(...)` nunca é chamado, a posição real do player e o
valor mostrado na barra ficam potencialmente dessincronizados até a próxima atualização
de `timemodel.currentTime` vinda do próprio player (que só volta a chegar quando ele
retomar a reprodução).

**Correção sugerida:** tratar `.cancelled`/`.failed` como `.ended` (chamar
`onEditingChanged(false)` ou reverter `value.wrappedValue = beganValue` e então
notificar `onEditingChanged(false)` de qualquer forma, garantindo que o player nunca
fique preso pausado por um gesto interrompido).

---

## 3. [ALTA] Erros de reprodução nunca chegam à UI do tvOS — `onFinish` não é conectado

**Arquivos:** `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:111-127` (`playView`)
cruzado com `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:274-276`
(`player(layer:finish:)`) e `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:367-403`
(rodapé tvOS)

O `Coordinator` expõe um callback dedicado a erros:

```swift
// KSVideoPlayer.swift:274-276
public func player(layer: KSPlayerLayer, finish error: Error?) {
    onFinish?(layer, error)
}
```

Só que `playView`, em `KSVideoPlayerView.swift`, conecta apenas `.onStateChanged` e
`.onBufferChanged`:

```swift
private var playView: some View {
    KSVideoPlayer(coordinator: playerCoordinator, url: url, options: options)
        .onStateChanged { playerLayer, state in ... }
        .onBufferChanged { bufferedCount, consumeTime in
            print("bufferedCount \(bufferedCount), consumeTime \(consumeTime)")
        }
    ...
```

`.onFinish { ... }` nunca é chamado. Ou seja, o `error: Error?` real (motivo do
`AVError`/erro do FFmpeg — DRM, codec não suportado, falha de rede, URL inválida etc.) é
descartado silenciosamente; a única coisa que a UI do tvOS faz com um erro é o troca de
ícone do botão de play/pause em `VideoControllerView` (`KSVideoPlayerView.swift:385`):

```swift
Image(systemName: config.state == .error ? "play.slash.fill" : ...)
```

Não existe nenhum texto, alerta ou mensagem explicando o que falhou — só um ícone
pequeno (renderizado em `.font(.caption)`, ver finding 7) que troca de forma. Um usuário
a alguns metros da TV, sem estar olhando exatamente para o botão de play no momento da
falha, não recebe nenhuma indicação de que o vídeo parou por erro (vs. pausado por ele
mesmo, vs. chegou ao fim).

**Cenário concreto de falha:** o stream falha (link expirado, DRM, formato não suportado
pelo decoder escolhido). `state` vira `.error`, os controles aparecem (`isMaskShow =
true`, branch `else` de `player(layer:state:)`), mas a única pista visual é o ícone de
play virar "play.slash.fill" — sem texto, sem motivo, sem sugestão de ação. O
`error: Error?` com a causa real nunca sai do `Coordinator`.

**Correção sugerida:** conectar `.onFinish` em `playView` e propagar a mensagem de erro
(ex.: `error?.localizedDescription`) para um texto visível no rodapé/overlay do tvOS
quando `config.state == .error`.

---

## 4. [MÉDIA] Sem indicador de carregamento no `.preparing` inicial no tvOS

**Arquivo:** `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:367-376`

No rodapé tvOS de `VideoControllerView`, o spinner de carregamento só aparece para o
estado `.buffering`:

```swift
Text(title).lineLimit(2).layoutPriority(3)
ProgressView()
    .opacity(config.state == .buffering ? 1 : 0)
```

O ciclo de vida do player (`KSPlayerState`, `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:26-57`)
tem um estado `.preparing` distinto de `.buffering`, usado exatamente no carregamento
inicial (antes do primeiro quadro pronto) — ver `KSPlayerLayer.swift:489`. Só que a
condição do `ProgressView` não inclui `.preparing`: o spinner fica com `opacity(0)`
durante toda a fase de abertura/carregamento inicial do vídeo.

**Cenário concreto de falha:** o usuário abre um título; enquanto o player está em
`.preparing` (resolvendo URL, abrindo o demuxer, etc. — pode levar alguns segundos em
streams de rede), os controles já estão visíveis (`isMaskShow = true`, branch `else` de
`player(layer:state:)`) mas o ícone mostrado é o de "play" normal
(`config.state.isPlaying` é `false` para `.preparing`, já que `isPlaying` só cobre
`.buffering`/`.bufferFinished` — `KSPlayerLayer.swift:56`) e **nenhum spinner** aparece.
A tela parece parada/travada, sem qualquer indicação de que o app está de fato
carregando algo.

**Correção sugerida:** trocar a condição para
`config.state == .buffering || config.state == .preparing`.

---

## 5. [MÉDIA] Avanço/retrocesso de 15s pelo remoto do tvOS não dá nenhum feedback visual quando os controles estão escondidos

**Arquivos:** `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:196-210` (gesto) e
`Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:176-184` (`skip`/`seek`)

```swift
.onMoveCommand { direction in
    switch direction {
    case .left:
        playerCoordinator.skip(interval: -15)
    case .right:
        playerCoordinator.skip(interval: 15)
    ...
```

```swift
public func skip(interval: Int) {
    if let playerLayer {
        seek(time: playerLayer.player.currentPlaybackTime + TimeInterval(interval))
    }
}

public func seek(time: TimeInterval) {
    playerLayer?.seek(time: TimeInterval(time))
}
```

Nem `skip(interval:)` nem `seek(time:)` tocam em `isMaskShow`. A única forma de a barra
de controles/tempo aparecer depois de um skip é indiretamente, via uma transição de
estado do player (`.buffering`/`.error`/etc. no `else` de `player(layer:state:)`,
`KSVideoPlayer.swift:237-238`) — o que só acontece se o seek de fato disparar rebuffer.

**Cenário concreto de falha:** depois que a barra de controles some sozinha (auto-hide
padrão de `KSOptions.animateDelayTimeInterval`, 5s), o foco volta para `.play`
(`VideoTimeShowView.onDisappear`, `KSVideoPlayerView.swift:236-238`), habilitando o
`onMoveCommand`. O usuário arrasta ←/→ no touchpad do remoto para pular ±15s repetidas
vezes. Se o conteúdo já está bufferizado no ponto de destino (comum em arquivos locais
ou HLS com buffer generoso), não há rebuffer, `state` não muda, e o usuário não vê
nenhum "+15s"/tempo atual/qualquer confirmação — só descobre onde parou se
explicitamente apertar ↑ ou ↓ para reabrir a barra completa. Diferente do Infuse (e da
versão paga do KSPlayer), que mostram um toast/preview do novo tempo a cada skip.

**Correção sugerida:** chamar `playerCoordinator.mask(show: true)` (ou um toast dedicado
de seek) dentro dos cases `.left`/`.right` do `onMoveCommand`, similar ao que o player
UIKit legado já faz com `SeekView`/`showSeekToView` (`Sources/KSPlayer/Video/VideoPlayerView.swift:638-655`).

---

## 6. [MÉDIA] Gesture recognizers de swipe se acumulam no `player.view` a cada novo vídeo carregado com a mesma engine

**Arquivos:** `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:239-253` (adição dos
recognizers) cruzado com `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:142-158`
(`url` `didSet`)

Toda vez que o delegate recebe `state == .preparing`, o `Coordinator` adiciona **4 novos**
`UISwipeGestureRecognizer` (`up`/`down`/`left`/`right`) na `view` do player:

```swift
if state == .preparing, let view = layer.player.view {
    let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(swipeGestureAction(_:)))
    swipeDown.direction = .down
    view.addGestureRecognizer(swipeDown)
    ... (idem para left/right/up)
}
```

Não há nenhuma remoção prévia (`removeGestureRecognizer`) nem guarda de "só adicionar uma
vez". Quando o usuário troca de vídeo dentro da mesma sessão do player (ex.: fluxo de
"próximo episódio" do StreamHub) usando a mesma engine (`KSAVPlayer`/`KSMEPlayer`), o
`url` `didSet` de `KSPlayerLayer` (`KSPlayerLayer.swift:142-158`) chama
`player.replace(url:options:)` e `prepareToPlay()` **sem recriar** o `player` (nem,
portanto, a `player.view`) — o `player` só é recriado se o tipo de engine mudar
(`KSPlayerLayer.swift:154-157`). Ou seja, a mesma `UIView` passa por `.preparing`
novamente a cada troca de título, e ganha mais 4 gesture recognizers idênticos, sem
nunca perder os antigos.

**Cenário concreto de falha:** o usuário assiste vários episódios em sequência na mesma
tela do player (troca de `url` via `openURL`/reabertura do mesmo `KSVideoPlayer.Coordinator`).
Depois de N trocas, a `view` acumula `4×N` gesture recognizers de swipe, todos
disparando o mesmo handler (`isMaskShow = true`) a cada gesto — trabalho redundante que
cresce sem limite durante a sessão do app, e que só é limpo quando o `Coordinator`
inteiro é desalocado (`resetPlayer()`, que zera `playerLayer` mas não desregistra
recognizers adicionados diretamente na `UIView` antiga).

**Correção sugerida:** adicionar os 4 recognizers uma única vez (ex.: guardar uma flag
`didAddSwipeGestures` no `Coordinator`, ou registrá-los em `makeView(url:options:)` em
vez de a cada `.preparing`).

---

## 7. [BAIXA] Ícones dos controles do tvOS renderizados em `.caption` — bem menores que os equivalentes de iOS/macOS/xrOS

**Arquivo:** `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift:367-403`

A barra de controles do tvOS (`VideoControllerView`, branch `#if os(tvOS)`) aplica
`.font(.caption)` a todo o `HStack` de botões (play/pause, áudio, mudo, modo de
conteúdo, legenda, velocidade, PiP, info — linha 402), enquanto o mesmo módulo usa
explicitamente `.font(.largeTitle)` para os botões equivalentes de play/pause/skip nas
demais plataformas (`Sources/KSPlayer/SwiftUI/KSVideoPlayerViewBuilder.swift:150,166,184`,
usadas em `playbackControlView`). Como esses botões renderizam `Image(systemName:)` (SF
Symbols), o tamanho do glifo segue diretamente o `Font` aplicado — `.caption` é a fonte
de legenda pequena do sistema, não um tamanho pensado para interface de "10 pés" (TV
vista a alguns metros de distância).

**Cenário concreto de falha:** em uma Apple TV normal, os ícones de play/pause, mudo,
modo de conteúdo, legendas, velocidade, PiP e info aparecem visivelmente menores e mais
difíceis de mirar com o foco/remoto do que o padrão usado nas outras plataformas do
mesmo player — o oposto do que se espera de uma UI de tvOS, que normalmente amplia alvos
de foco em vez de encolhê-los.

**Correção sugerida:** usar um tamanho de fonte maior e mais consistente com o restante
do player (`.title`/`.largeTitle`) para os botões do rodapé tvOS.

---

## Observações relacionadas (não reportadas como findings separados)

- `VideoSettingView` (`KSVideoPlayerView.swift:667-717`) só tem um botão "Done" explícito
  para `#if os(macOS) || targetEnvironment(macCatalyst) || os(xrOS)` — no tvOS, fechar o
  painel de informações depende inteiramente do botão Menu/Voltar do remoto via
  `onExitCommand` (`KSVideoPlayerView.swift:96-107`). Funciona (confirmado seguindo a
  cadeia `focusableField` → `isDropdownShow`), mas não há nenhuma affordance visual
  indicando isso dentro do próprio painel.
- `MenuView` (`KSVideoPlayerView.swift:519-552`) tem um fallback para tvOS < 17 que usa
  `Picker(...).pickerStyle(.navigationLink)`. Não consegui validar em runtime o
  comportamento desse estilo especificamente em tvOS 16 (o repo não tem simulador
  disponível nesta auditoria); vale um teste manual num dispositivo/simulador tvOS 16 se
  esse alvo ainda for suportado pelo StreamHub.
