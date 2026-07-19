# Auditoria de ciclo de vida — KSPlayer (fork StreamHub)

Escopo: `Sources/` do fork GPL do KSPlayer. Foco: ordem de setup/teardown do player,
AVAudioSession, DisplayLink/timers não invalidados, PiP, background/foreground,
deinit incompleto e reuso do player para um novo item.

Cada finding abaixo foi confirmado lendo o código (arquivo/linha citados) e, quando o
comportamento depende de API da Apple, verificado contra a documentação oficial.

---

## 1. [CRÍTICA] `KSPlayerLayer.timer` nunca é invalidado — leak de Timer a cada troca/descarte de player

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:175-187` (declaração do timer) e `:240-259` (`deinit`)

```swift
private lazy var timer: Timer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
    guard let self, self.player.isReadyToPlay else { return }
    ...
}
```

`timer` é criado com `Timer.scheduledTimer`, que a documentação da Apple descreve
explicitamente como "the run loop keeps a reference to the timer object" — ou seja, o
próprio `RunLoop.main` retém o `Timer` até que `invalidate()` seja chamado, independente
de quem (ou se alguém) ainda guarda uma referência Swift para ele.

Em todo o arquivo, o timer só é manipulado via `fireDate` (`.distantPast` para religar,
`.distantFuture` para pausar) em `play()` (linha 298), `pause()` (linha 310) e
`finish(player:error:)` (linha 460). **Nunca há uma chamada a `timer.invalidate()`**,
nem mesmo no `deinit` (linhas 240-259), que remove observers de `NotificationCenter` e
`MPRemoteCommandCenter` mas não toca no timer.

**Cenário concreto de falha:** `PlayerView.set(url:options:)`
(`Sources/KSPlayer/Core/PlayerView.swift:150-155`) troca de vídeo assim:

```swift
open func set(url: URL, options: KSOptions) {
    srtControl.url = url
    toolBar.currentTime = 0
    totalTime = 0
    playerLayer = KSPlayerLayer(url: url, options: options)   // descarta o layer antigo
}
```

Não há chamada a `.stop()`/`.pause()` no `playerLayer` antigo antes de substituí-lo. Se o
usuário estava assistindo um vídeo (timer com `fireDate = .distantPast`) e troca para
outro título, o `KSPlayerLayer` antigo perde sua única referência forte e é
desalocado — mas o `Timer` de 100ms que ele criou continua agendado no
`RunLoop.main` para sempre, disparando 10x/segundo (o `guard let self` vira no-op, mas o
wake-up do run loop continua ocorrendo). A cada troca de título dentro de uma mesma
sessão do app, mais um desses timers "zumbis" se acumula, consumindo CPU/bateria
indefinidamente — só termina quando o processo do app é encerrado.

Mesmo no caminho "limpo" (`stop()`, linha 318-330), o timer fica em `.distantFuture`
(pausado) mas nunca invalidado — o objeto `Timer` continua ocupando o run loop pelo resto
da vida do processo; é um leak de memória menor, mas ainda incorreto.

**Correção sugerida:** invalidar o timer em `deinit` e em `stop()`.

---

## 2. [ALTA] `AVAudioSession` é ativada mas nunca desativada em nenhum ponto do código

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSOptions.swift:494-509`

```swift
static func setAudioSession() {
    ...
    try? AVAudioSession.sharedInstance().setActive(true)
    ...
}
```

`setAudioSession()` é chamado em todo `init` de player:
`KSMEPlayer.init(url:options:)` (`Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:118`) e
`KSAVPlayer.init(url:options:)` (`Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:215`).

Busquei `setActive` em todo `Sources/` e a única ocorrência é esse `setActive(true)` —
**não existe nenhum `setActive(false)` no projeto**. Nem `KSPlayerLayer.stop()`
(linhas 318-330), nem `KSMEPlayer.shutdown()` (linhas 405-426), nem
`KSAVPlayer.shutdown()` (linhas 439-446), nem qualquer `deinit`, devolvem a sessão de
áudio.

**Cenário concreto de falha:** o usuário fecha o player por completo (sem background
play habilitado). A app nunca chama `setActive(false)`, então a
`AVAudioSession` compartilhada do processo continua ativa na categoria
`.playback`/`.moviePlayback` (`policy: .longFormAudio/.longFormVideo`) mesmo depois que
todo o player foi desalocado. Isso é o oposto do padrão documentado pela Apple
("deactivate your app's audio session when audio playback finishes") e pode manter o
app segurando o foco de áudio desnecessariamente, afetando qualquer outro subsistema de
áudio do StreamHub (ex.: sons de UI, outro player secundário) que dependa de uma sessão
neutra.

---

## 3. [ALTA] Troca para o segundo player (fallback de erro) descarta o player antigo sem chamar `shutdown()`

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift:444-449` (`finish(player:error:)`)
comparado com `:142-158` (`url` didSet)

No `didSet` de `url`, quando é preciso trocar de engine, o código primeiro chama
`stop()` (que executa `player.shutdown()` no player **ainda antigo**, pois a atribuição
só acontece na linha seguinte):

```swift
} else {
    stop()
    player = firstPlayerType.init(url: url, options: options)
}
```

Já no fallback de erro (`finish(player:error:)`), o `player` é substituído **sem** essa
chamada:

```swift
public func finish(player: some MediaPlayerProtocol, error: Error?) {
    if let error {
        if type(of: player) != KSOptions.secondPlayerType, let secondPlayerType = KSOptions.secondPlayerType {
            self.player = secondPlayerType.init(url: url, options: options)
            return
        }
        ...
```

O `player` `didSet` (linhas 96-126) reposiciona a view mas também não chama
`oldValue.shutdown()` — o teardown do player que acabou de falhar depende inteiramente
de o objeto ser desalocado pelo ARC e de a classe concreta ter um `deinit` que faça a
limpeza sozinha.

Isso funciona "por acidente" para `KSMEPlayer`, cujo `deinit`
(`Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:140-147`) chama `playerItem.shutdown()`.
Mas **`KSAVPlayer` não tem `deinit` nenhum** (confirmado: nenhuma ocorrência de `deinit`
em `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift`). Ou seja, quando o player que falhou é
um `KSAVPlayer`, o `shutdown()` daquela instância — que faz
`urlAsset.cancelLoading()` e `replaceCurrentItem(playerItem: nil)`
(`KSAVPlayer.swift:439-446`) — **nunca é executado**. O cancelamento explícito do
carregamento do asset (relevante para fontes com resource loader customizado/DRM ou
streams remotos ainda carregando quando o erro ocorreu) fica só a cargo do ARC ao
desalocar `AVQueuePlayer`/`AVPlayerItem` em cascata, sem a garantia determinística que o
próprio código já expressa (via `shutdown()`) ser necessária no caminho feliz.

**Correção sugerida:** chamar `player.shutdown()` (ou `stop()`) sobre o player antigo
antes de atribuir `self.player = secondPlayerType.init(...)`, e/ou adicionar um `deinit`
a `KSAVPlayer` que garanta o mesmo teardown que `shutdown()` já faz.

---

## 4. [MÉDIA] Timer do `AVDelegatingPlaybackCoordinator` (buffering) nunca é agendado — nunca dispara

**Arquivo:** `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift:547-566`

```swift
public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue bufferingCommand: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping () -> Void) {
    ...
    self.bufferingCountDownTimer?.invalidate()
    self.bufferingCountDownTimer = nil
    self.bufferingCountDownTimer = Timer(timeInterval: countDown, repeats: false) { _ in
        completionHandler()
    }
}
```

`Timer(timeInterval:repeats:block:)` (o inicializador "cru", sem `scheduled`) **não**
agenda o timer em nenhum run loop automaticamente — é necessário chamar
`RunLoop.current.add(timer, forMode:)` manualmente (diferente de
`Timer.scheduledTimer`, que agenda sozinho no run loop atual). O código aqui nunca faz
esse `add(_:forMode:)`.

**Cenário concreto de falha:** quando o `AVDelegatingPlaybackCoordinator` (usado para
reprodução coordenada, ex. SharePlay/GroupActivities) emite um `bufferingCommand` com um
`completionDueDate` no futuro, o `Timer` criado fica órfão — nunca dispara — e
`completionHandler()` nunca é chamado. O comando de buffering fica pendente
indefinidamente, travando a sincronização de reprodução coordenada nesse ponto
específico.

**Correção sugerida:** usar `Timer.scheduledTimer(withTimeInterval:repeats:block:)` ou
adicionar explicitamente `RunLoop.current.add(bufferingCountDownTimer!, forMode: .common)`.

---

## Observações relacionadas (não reportadas como findings separados)

- `KSVideoPlayer.Coordinator.playerLayer` (`Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift:120-125`)
  também só chama `oldValue?.pause()` ao trocar/zerar o `playerLayer`, nunca `.stop()`.
  Funciona hoje porque a desalocação do `KSPlayerLayer` antigo dispara o `deinit` da
  engine concreta (`KSMEPlayer.deinit` chama `playerItem.shutdown()`), mas é a mesma
  dependência implícita descrita no finding 3 — qualquer novo `MediaPlayerProtocol` que
  não replique esse `deinit` vai vazar recursos de decodificação/rede silenciosamente.
- `KSMEPlayer.enterBackground()`/`enterForeground()` (linhas 442-444) são no-ops,
  enquanto `KSAVPlayer` desconecta/reconecta a `AVPlayerLayer` do `AVQueuePlayer`
  (`KSAVPlayer.swift:464-470|`). Não constatei um caminho de falha concreto (o
  `CADisplayLink` da `MetalPlayView` tende a ser suspenso pelo sistema quando o app vai
  para background), mas é uma assimetria entre as duas engines que vale revisar ao
  perseguir paridade de background-play com o Infuse.
