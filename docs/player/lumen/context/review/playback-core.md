# Auditoria de núcleo de playback — KSPlayer fork

Escopo: `Sources/` (KSPlayer). Foco: seek (casos extremos, seek durante buffering),
sincronização A/V (clocks), buffering/rebuffering, transições da máquina de estados,
loop/replay, troca de tracks no meio da reprodução. Backends cobertos: `KSMEPlayer`
(FFmpeg/`MEPlayerItem`) e `KSAVPlayer` (AVFoundation nativo).

Nota de escopo: o problema de `NSCondition` usado sem `lock()`/`unlock()` em
`MEPlayerItem.readThread()`/`pause()`/`resume()` (que também causa travamento de
buffering/rebuffering por sinal perdido) já está documentado em detalhe em
`context/review/concorrencia.md` (achados 1 e 2), assim como o leak de `decoderMap` em
`SyncPlayerItemTrack.shutdown()` (`context/review/memoria.md`, achado 1). Não repito
esses dois aqui para evitar duplicação — os achados abaixo são independentes deles.

---

## 1. [ALTA] Seek perde precisão de até ~1s por truncamento prematuro para `Int64`

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linhas:** 453–480 (bloco `if state == .seeking` dentro de `readThread()`), especialmente
456 e 478–479

```swift
let seekToTime = seekTime
let time = mainClock().time
var increase = Int64(seekTime + startTime.seconds - time.seconds)   // linha 456
...
} else {
    increase *= Int64(AV_TIME_BASE)
    timeStamp = Int64(time.seconds) * Int64(AV_TIME_BASE) + increase   // linhas 478–479
}
```

O delta entre a posição atual e o tempo alvo do seek (`seekTime + startTime.seconds -
time.seconds`, um `Double` com parte fracionária real, pois `time` vem de um clock
contínuo) é truncado para `Int64` **antes** de ser multiplicado por `AV_TIME_BASE`
(1_000_000). Isso descarta a parte fracionária de segundo do delta inteiro, não apenas
uma micro-precisão de microssegundos — o alvo passado para `avformat_seek_file` pode
ficar até quase 1 segundo distante do que o usuário pediu.

A direção do erro depende do sinal do seek:
- **Seek para frente:** `Int64()` trunca em direção a zero, então o alvo enviado ao
  demuxer fica um pouco **antes** do solicitado (subestimativa). Com
  `options.isAccurateSeek == true` isso é inofensivo, pois `SyncPlayerItemTrack.seek(time:)`
  guarda o `seekTime` exato e o decode descarta frames até alcançá-lo
  (`MEPlayerItemTrack.swift:145–153`). Mas com o padrão de fábrica
  (`KSOptions.isAccurateSeek = false`, `KSOptions.swift:470`), `seekTime` fica zerado
  (`MEPlayerItemTrack.swift:73–77`) e **não há nenhuma correção** — o vídeo simplesmente
  recomeça a tocar até ~1s antes do ponto pedido.
- **Seek para trás:** o mesmo truncamento reduz a magnitude do delta negativo, então o
  alvo enviado ao demuxer fica até ~1s **depois** do solicitado — na direção errada para
  a lógica de "seek exato" funcionar, já que essa lógica só compensa frames decodificados
  **depois** do ponto de destino, nunca antes. Se o keyframe mais próximo (com
  `AVSEEK_FLAG_BACKWARD`) cair entre o alvo real e o alvo truncado — bem provável em
  streams com GOP curto —, o primeiro frame decodificado já satisfaz
  `frame.seconds >= seekTime` e é aceito sem nenhum recorte, mesmo estando até ~1s depois
  do que o usuário pediu.

**Cenário concreto de falha:** com as configurações padrão do fork (`isAccurateSeek =
false`), o usuário arrasta a barra de progresso do tvOS para qualquer ponto do vídeo. Em
praticamente todo seek, a posição de retomada da reprodução fica deslocada em até quase 1
segundo do ponto solicitado (para trás no caso de seek reverso, para frente no caso de
seek adiante) — um comportamento sistemático, não um caso raro, porque decorre de uma
truncagem que ocorre em toda chamada de seek, e não de arredondamento de keyframe do
demuxer (que já seria esperado e menor).

---

## 2. [ALTA] Loop "sem costura" quebra a cada segunda repetição e desalinha legendas embutidas, porque `SyncPlayerItemTrack` não participa do buffer duplo de `isLoopModel`

**Arquivos:**
`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` (linhas 570–576, 717–734)
`Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift` (linhas 42, 72–82, 84–92, 186–202)

Quando `options.isLoopPlay` está ativo e o fim do arquivo é atingido, `reading()` decide
entre loop "sem costura" (pré-bufferizando a próxima volta antes de a atual acabar) e
reinício "duro" via seek:

```swift
// MEPlayerItem.swift:570-576
if options.isLoopPlay, allPlayerItemTracks.allSatisfy({ !$0.isLoopModel }) {
    allPlayerItemTracks.forEach { $0.isLoopModel = true }
    _ = av_seek_frame(formatCtx, -1, startTime.value, AVSEEK_FLAG_BACKWARD)
} else {
    allPlayerItemTracks.forEach { $0.isEndOfFile = true }
    state = .finished
}
```

`allPlayerItemTracks` inclui **todas** as tracks, inclusive as de legenda embutida
(`assetTrack.subtitle`, sempre um `SyncPlayerItemTrack<SubtitleFrame>` —
`MEPlayerItem.swift:339–343`). Só que:

- `AsyncPlayerItemTrack.isLoopModel` (usada por vídeo/áudio no modo assíncrono padrão)
  tem um `didSet` (linhas 186–202) que cria uma `loopPacketQueue` separada e marca
  `isEndOfFile = true`, isolando os pacotes da "próxima volta" dos da volta atual até o
  momento certo de trocar.
- `SyncPlayerItemTrack.isLoopModel` (linha 42) é uma propriedade simples, **sem** esse
  comportamento. E `SyncPlayerItemTrack.putPacket` (linhas 84–92) nunca checa
  `isLoopModel` — ele decodifica e empurra o frame pra `outputRenderQueue`
  **imediatamente**, não importa de qual volta o pacote seja.

Isso tem dois efeitos concretos:

1. **Desalinhamento de legenda:** assim que o `av_seek_frame` de loop acontece, pacotes
   de legenda da *próxima* volta (timestamps baixos, próximos de `startTime`) já chegam e
   são decodificados na hora, indo parar na mesma `outputRenderQueue`
   (`sorted: true`, `MEPlayerItemTrack.swift:63`) que ainda tem frames de legenda do
   *fim* da volta atual (timestamps altos) esperando para ser exibidos. A fila ordenada
   por timestamp acaba intercalando texto de legenda da próxima exibição com o final da
   atual — o usuário vê legendas da cena errada, ou o clock do fim da volta atual mostra
   texto que na verdade pertence ao começo da próxima.
2. **Loop deixa de ser "sem costura" a cada segunda repetição:** `codecDidFinished`
   (linhas 717–734) só reseta `isLoopModel` de volta para `false` em `audioTrack` e
   `videoTrack` (linhas 727–728) — a track de legenda (que também foi marcada
   `isLoopModel = true` na linha 571) nunca é resetada ali. Na volta seguinte,
   `allPlayerItemTracks.allSatisfy({ !$0.isLoopModel })` (linha 570) já não é mais `true`
   (a legenda ainda está com `true`), então o código cai no `else` — reinício "duro":
   `state = .finished`, thread de leitura para, e só volta a tocar quando
   `codecDidFinished` perceber `state == .finished` e chamar `seek(time: 0)` (linha 730).
   Esse caminho de seek genérico *aí sim* zera `isLoopModel` de todas as tracks via
   `SyncPlayerItemTrack.seek(time:)` (linha 81), então a volta seguinte volta a ser "sem
   costura" — e a próxima depois dessa, "dura" de novo. O padrão fica alternado:
   volta 1 sem costura, volta 2 com engasgo perceptível (buffer zerado, espera reabrir
   decode), volta 3 sem costura, volta 4 com engasgo, e assim por diante.

**Cenário concreto de falha:** um clipe curto com legenda embutida (comum em rips
MKV/MP4) tocando com `isLoopPlay = true` (o próprio comentário do código, "Applies to
short videos only", descreve exatamente esse uso). A cada repetição par, o usuário sente
uma pausa/engasgo perceptível no loop que deveria ser contínuo; e a qualquer momento, o
texto da legenda pode aparecer fora de ordem (da próxima volta, sobreposto ao fim da
atual) por causa da falta de isolamento em `SyncPlayerItemTrack.putPacket`.

---

## 3. [ALTA] `avcodec_send_packet` retornando `EAGAIN` descarta o pacote em silêncio, sem drenar frames pendentes

**Arquivo:** `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift`
**Linha:** 38

```swift
func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
    guard let codecContext, avcodec_send_packet(codecContext, packet.corePacket) == 0 else {
        return
    }
    ...
```

Pela própria documentação da API send/receive do FFmpeg (`avcodec_send_packet`), um
retorno `AVERROR(EAGAIN)` não é um erro fatal — significa "o buffer interno do decoder
está cheio; leia a saída com `avcodec_receive_frame()` e reenvie o pacote depois, que
essa segunda tentativa não vai falhar com EAGAIN". É um retorno esperado e documentado do
laço de decodificação, não uma falha. Aqui, qualquer retorno diferente de `0` — inclusive
`EAGAIN` — cai no `guard ... else { return }` e:

- o laço `while true { avcodec_receive_frame(...) }` (linha 58 em diante) **nunca roda**
  para esse pacote, então os frames que já estavam prontos no decoder não são drenados
  agora (só na próxima chamada, se houver, e só se o decoder aceitar o próximo pacote —
  mas como o buffer estava cheio, provavelmente vai rejeitar de novo, criando um ciclo);
- o próprio `packet` que causou o `EAGAIN` é **descartado sem reenvio** — nunca é
  decodificado;
- nenhum log, contador de frame dropado ou erro é reportado; o `completionHandler` nem é
  chamado (nem sucesso, nem falha) para esse pacote.

**Cenário concreto de falha:** o decoder de vídeo/áudio acumula uma fila de saída
temporária maior que 1 frame (reordenamento de B-frames, latência inicial do decodificador
de hardware, ou simplesmente um pico de pacotes entregues em rajada pela thread de
leitura). `avcodec_send_packet` responde `EAGAIN` para o próximo pacote. O código
descarta esse pacote e segue em frente sem nunca chamar `avcodec_receive_frame` para
esvaziar o que já estava pronto — na prática, perde silenciosamente um ou mais frames
consecutivos exatamente no momento em que o decoder está sob mais pressão, produzindo
saltos/artefatos visuais ou de áudio e, cumulativamente, desvio entre o clock de
áudio e o de vídeo (já que os frames perdidos nunca chegam a `setVideo`/`setAudio` em
`MEPlayerItem`) sem qualquer sinal de erro no log para diagnosticar a causa.

---

## 4. [MÉDIA] `sourceDidFinished()` força `play()` no áudio/vídeo ao reiniciar o loop, ignorando um `pause()` explícito do usuário

**Arquivo:** `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift`
**Linhas:** 224–236

```swift
func sourceDidFinished() {
    runOnMainThread { [weak self] in
        guard let self else { return }
        if self.options.isLoopPlay {
            self.loopCount += 1
            self.delegate?.playBack(player: self, loopCount: self.loopCount)
            self.audioOutput.play()
            self.videoOutput?.play()
        } else {
            self.playbackState = .finished
        }
    }
}
```

Quando `MEPlayerItem` conclui a transição de loop (achado 2 acima) e notifica o
delegate, o ramo `isLoopPlay` chama `audioOutput.play()`/`videoOutput?.play()`
**diretamente**, sem passar pelo caminho normal (`playbackState = .playing` →
`playOrPause()`, que checa `playbackState == .playing && loadState == .playable` antes de
tocar — ver linhas 103–115 e 153–166). Isso ignora completamente o estado atual de
`playbackState`.

**Cenário concreto de falha:** o usuário pausa a reprodução (`pause()`, que seta
`playbackState = .paused` e chama `audioOutput.pause()`/`videoOutput?.pause()`)
exatamente perto do fim de um clipe curto em loop. Se o boundary do loop (detectado de
forma assíncrona pela thread de leitura/decode, ver achado 2) só chega ao
`sourceDidFinished()` depois desse pause — cenário bem provável já que loops curtos
disparam esse callback com frequência — o áudio e o vídeo voltam a tocar sozinhos
(`audioOutput.play()`/`videoOutput?.play()` são chamados incondicionalmente), mesmo com
`self.playbackState` continuando `== .paused` internamente. O app fica com o estado
interno dizendo "pausado" enquanto o motor de áudio/vídeo está de fato tocando —
inconsistência que só se resolve se o usuário mexer de novo em play/pause.

---

## 5. [MÉDIA] Seek do `AVPlaybackCoordinator` pode crashar com `duration == 0` (stream ao vivo/duração desconhecida)

**Arquivo:** `Sources/KSPlayer/MEPlayer/KSMEPlayer.swift`
**Linha:** 540

```swift
public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue seekCommand: AVDelegatingPlaybackCoordinatorSeekCommand) async {
    guard seekCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
        return
    }
    let seekTime = fmod(seekCommand.itemTime.seconds, duration)   // linha 540
    if abs(currentPlaybackTime - seekTime) < CGFLOAT_EPSILON {
        return
    }
    seek(time: seekTime) { _ in }
}
```

`duration` é `playerItem.duration`, que fica `0` para streams ao vivo/de duração
desconhecida (`MEPlayerItem.swift`: `duration = TimeInterval(max(formatCtx.pointee.duration, 0) / ...)`,
suportado explicitamente pelo fork — ver os comentários sobre streams `ts` ao vivo em
`KSOptions.swift`). `fmod(x, 0)` é `NaN` por definição (IEEE 754). A comparação seguinte
(`abs(...) < CGFLOAT_EPSILON`) com `NaN` é sempre `false` (comparações com `NaN` nunca são
verdadeiras), então o código **não retorna cedo** e chama `seek(time: .nan)`.

Isso propaga para `KSMEPlayer.seek(time:completion:)` (linha 356: `let time = max(time, 0)`
— `max` com `NaN` também retorna `NaN`) e daí para `playerItem.seek(time: .nan)` em
`MEPlayerItem`. Dentro de `readThread()`, ao processar o seek,
`Int64(seekTime + startTime.seconds - time.seconds)` (`MEPlayerItem.swift:456`) vira
`Int64(Double.nan)`, que é uma conversão que **trapa em tempo de execução** em Swift
("Fatal error: NaN cannot be converted to Int64") — derruba o processo.

**Cenário concreto de falha:** um usuário assiste a um canal de TV ao vivo (duração
desconhecida/zero) dentro de uma sessão do `AVDelegatingPlaybackCoordinator` (SharePlay/
GroupActivities) e outro participante da sessão emite um comando de seek — ou o próprio
sistema reemite um comando de seek de sincronização de coordenador. O app derruba
imediatamente por causa da conversão `NaN → Int64`.

---

## Resumo por severidade

| # | Achado | Dimensão | Severidade |
|---|--------|----------|------------|
| 1 | Truncamento prematuro pra `Int64` no cálculo do seek (`readThread`) | seek | alta |
| 2 | `isLoopModel` não tratado por `SyncPlayerItemTrack` — legenda dessincroniza e loop perde a "costura" a cada 2ª volta | loop/replay | alta |
| 3 | `avcodec_send_packet` com `EAGAIN` descarta pacote/frame em silêncio | buffering / decode | alta |
| 4 | `sourceDidFinished()` força `play()` no reinício do loop, ignorando `pause()` do usuário | loop/replay / máquina de estados | media |
| 5 | `fmod(_, duration: 0)` gera `NaN` e crasha em seek via `AVPlaybackCoordinator` | seek | media |

Não repetidos aqui (já cobertos por outros documentos desta auditoria):
`NSCondition` sem `lock()/unlock()` em `MEPlayerItem` (buffering/rebuffering) —
`context/review/concorrencia.md` achados 1–2; leak de `decoderMap` em
`SyncPlayerItemTrack.shutdown()` — `context/review/memoria.md` achado 1.
