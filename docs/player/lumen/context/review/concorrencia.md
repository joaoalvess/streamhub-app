# Auditoria de concorrência — KSPlayer fork

Escopo: `Sources/` (KSPlayer + DisplayCriteria). Foco: estado compartilhado sem sincronização,
chamadas de UI fora da main thread, data races entre threads de decode/render/demux, uso
incorreto de `DispatchQueue`/locks, deadlocks potenciais.

Contexto relevante encontrado no pipeline:

- `MEPlayerItem` roda `openThread`/`readThread` numa `OperationQueue` serial própria
  (thread "read"). Cada `PlayerItemTrackProtocol` (`AsyncPlayerItemTrack`) roda seu próprio
  `decodeThread` numa segunda `OperationQueue` serial (thread "decode", uma por track).
  O consumo (`getVideoOutputRender`/`getAudioOutputRender`) acontece a partir da UI: no
  vídeo, via `CADisplayLink` na main thread (`MetalPlayView`); no áudio, via callback de
  render em tempo real do Core Audio/AVAudioEngine (thread própria do SO). A única
  primitiva de sincronização real do pipeline é o `NSCondition` interno de `CircularBuffer`.
- `MEPlayerItem` é declarado `public final class MEPlayerItem: Sendable` (não
  `@unchecked Sendable`) mesmo tendo dezenas de `var` mutáveis sem lock. O pacote compila
  com `.enableExperimentalFeature("StrictConcurrency")` (`Package.swift`), então essa
  anotação está dando ao compilador (e a quem consome o tipo) uma falsa garantia de
  thread-safety que a implementação não entrega. Isso não é listado como finding isolado,
  mas explica por que vários dos problemas abaixo passam despercebidos pelo checker.

---

## 1. `NSCondition` usado sem `lock()`/`unlock()` — pode travar ou se comportar de forma indefinida

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linhas:** 18 (declaração), 451 (`condition.wait()`), 594 (`condition.signal()` em `resume()`),
663 (`condition.signal()` em `shutdown()`), 683 (`condition.broadcast()` em `seek(time:completion:)`)
**Severidade:** alta

`condition` é um `NSCondition`, mas em nenhum ponto do arquivo há uma chamada a
`condition.lock()`/`condition.unlock()`. `NSCondition.wait()` chama internamente
`pthread_cond_wait(cond, mutex)`, que exige que a *própria thread chamadora* já tenha
travado o mutex antes de esperar — caso contrário o comportamento é indefinido (POSIX).
Aqui `readThread()` chama `condition.wait()` (linha 451) sem nunca ter travado `condition`,
e `resume()`/`shutdown()`/`seek(time:completion:)` chamam `signal()`/`broadcast()` do mesmo
jeito, de threads diferentes (main thread via timer, thread de chamada de `seek`/`shutdown`).

**Cenário concreto de falha:** o usuário pausa o buffer (`pause()` setando `state = .paused`
a partir do timer na main thread) e o `readThread()` entra em `condition.wait()` sem lock.
Como não há mutex protegendo a seção, existe uma janela entre a checagem
`if state == .paused` e o `wait()` em que um `resume()` concorrente pode chamar
`condition.signal()` "antes" do wait — sinal perdido, thread de leitura fica bloqueada
para sempre (o player trava com playback nunca mais avançando) até um novo evento externo
mexer no estado. Em builds/plataformas onde o runtime valida titularidade do mutex, isso
também pode terminar em crash.

---

## 2. `MESourceState` (`state`) e `seekTime` sem sincronização entre main thread e thread de leitura

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linhas:** 61–77 (`state`), 449 (loop de leitura testando `state`), 585–596 (`pause()`/`resume()`),
678–695 (`seek(time:completion:)`)
**Severidade:** alta

`state` é lido/escrito por três atores concorrentes sem qualquer lock: (a) o `readThread()`
na thread "read" (linha 449 em diante); (b) `pause()`/`resume()`, chamados a partir de
`codecDidChangeCapacity()`, disparado pelo `Timer` de `lazy var timer` — como o timer é
criado/agendado na thread onde `MEPlayerItem` é inicializado (tipicamente a main thread), esse
caminho roda na main thread; (c) `seek(time:completion:)` e `select(track:)`, chamados pelo
código que usa `MediaPlayerProtocol` (não há `@MainActor` na protocol em si, então qualquer
thread pode chamar). Nenhuma dessas três vias usa lock — a única "sincronização" é o
`NSCondition` já quebrado (finding 1).

**Cenário concreto de falha:** durante buffering, o timer da main thread chama `resume()`
(`state = .reading; condition.signal()`) no exato instante em que o `readThread()` está
prestes a testar `if state == .paused` para decidir se deve esperar. Dependendo do
entrelaçamento, o `readThread()` pode ler `.paused` *depois* que o `resume()` já mudou para
`.reading` e sinalizou, entrando em `wait()` sem que ninguém mais vá acordá-lo — o player
fica "carregando" indefinidamente mesmo com dados disponíveis. Como o enum não é atômico e
não há barreira de memória entre as duas threads, o compilador/CPU pode inclusive reordenar
ou manter a leitura em cache, atrasando a visibilidade da mudança de estado.

---

## 3. `FFmpegAssetTrack.isEnabled` alternado concorrentemente com o roteamento de pacotes

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linhas:** 134–158 (`select(track:)`, escreve `isEnabled`), 551–567 (`reading()`, lê `first.isEnabled`)
**Severidade:** media

`select(track:)` é chamado pela API pública (`KSMEPlayer.select(track:)` → `MediaPlayerProtocol`,
tipicamente a partir da UI) e escreve `isEnabled` em vários `FFmpegAssetTrack` (linha 139:
`assetTracks.filter { ... }.forEach { $0.isEnabled = track === $0 }`). Ao mesmo tempo, a
thread de leitura (`reading()`, linha 552) lê `first.isEnabled` para decidir se um pacote lido
deve ser enviado à track de vídeo/áudio/legenda. `isEnabled` é um `var` simples, sem lock.

**Cenário concreto de falha:** o usuário troca a faixa de áudio durante a reprodução. Entre o
momento em que `select(track:)` desabilita a faixa antiga e habilita a nova (duas atribuições
separadas, não atômicas em conjunto) e a chamada subsequente de `seek(time:)` que deveria
"limpar" o pipeline, a thread de leitura pode observar um pacote da faixa antiga já com
`isEnabled == false` e descartá-lo silenciosamente, ou observar momentaneamente duas faixas
com `isEnabled == true` (se a leitura acontecer entre o `forEach` desabilitar uma e habilitar
outra) e enfileirar pacotes para ambas simultaneamente, gerando frames órfãos na fila da faixa
que está prestes a ser desativada.

---

## 4. `decoderMap` mutado concorrentemente pela callback assíncrona do VideoToolbox e pela thread de decode

**Arquivos:**
`Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift` (linhas 27, 130, 160–165)
`Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift` (linhas 30–94, callback em 50–78)
**Severidade:** critica

Quando o decode de hardware está ativo (`options.hardwareDecode` + `asynchronousDecompression`),
`VideoToolboxDecode.decodeFrame` chama `VTDecompressionSessionDecodeFrame` com a flag
`._EnableAsynchronousDecompression` (linha 42–44). Isso faz o `completionHandler` (o closure
passado por `SyncPlayerItemTrack.doDecode(packet:)`) ser invocado **numa thread interna do
VideoToolbox**, não na thread de decode que chamou `decodeFrame`. Dentro desse completion
(`MEPlayerItemTrack.swift` linhas 158–168), em caso de erro de decodificação de um frame não-chave,
o código faz:

```swift
if decoder is VideoToolboxDecode {
    decoder.shutdown()
    self.decoderMap[packet.assetTrack.trackID] = FFmpegDecode(assetTrack: packet.assetTrack, options: self.options)
    ...
    self.doDecode(packet: packet)
}
```

Isso escreve em `self.decoderMap` (um `[Int32: DecodeProtocol]`, sem nenhum lock) a partir da
thread de callback do VideoToolbox, enquanto a thread de decode (`decodeThread()` em
`AsyncPlayerItemTrack`, chamando `doDecode(packet:)` para o próximo pacote da fila) pode estar
simultaneamente lendo/escrevendo o mesmo dicionário via
`decoderMap.value(for: packet.assetTrack.trackID, default: makeDecode(...))` (linha 130).

**Cenário concreto de falha:** um stream HEVC com decodificação de hardware sofre um erro
recuperável (`kVTVideoDecoderMalfunctionErr`) num frame não-chave. A callback do VideoToolbox
dispara em sua própria thread e começa a escrever `self.decoderMap[trackID] = FFmpegDecode(...)`
exatamente quando a thread de decode, processando o próximo pacote da `packetQueue`, está no
meio de um rehash do mesmo `Dictionary` (inserindo/lendo outra entrada). Mutação concorrente de
`Dictionary` em Swift sem sincronização é undefined behavior e tipicamente manifesta como crash
(corrupção de memória / `EXC_BAD_ACCESS`) ou, na melhor das hipóteses, perda silenciosa do
decoder recém-criado.

---

## 5. `seekTime`/`state` de `SyncPlayerItemTrack` compartilhados entre thread de decode, callback do VideoToolbox, thread de leitura e main thread

**Arquivos:**
`Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift` (linhas 25, 72–82, 142–153)
`Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` (linha 824, `videoTrack.seekTime = mainClock().time.seconds`)
**Severidade:** alta

`seekTime` é escrito por `seek(time:)` (chamado a partir da thread de leitura dentro de
`readThread()`, linha 504/684 de `MEPlayerItem.swift`), lido e potencialmente zerado dentro do
completion de `doDecode` (linha 145–152 — que, para `VideoToolboxDecode`, roda na thread de
callback do VideoToolbox, ver finding 4), e também escrito diretamente por
`MEPlayerItem.getVideoOutputRender(force:)` no caso `.seek` (linha 824), que roda na **main
thread** (chamado a partir do `CADisplayLink` do `MetalPlayView`). Três threads distintas leem
e escrevem a mesma variável `Double` sem lock, junto com `state` (também lido dentro do mesmo
completion, linha 142).

**Cenário concreto de falha:** logo após um seek, a main thread ainda está processando o frame
anterior e escreve `videoTrack.seekTime = mainClock().time.seconds` (novo valor de seek "vindo
do lado do render"), enquanto a callback assíncrona do VideoToolbox, processando um frame que
já havia sido decodificado antes do seek, lê `self.seekTime` para decidir se descarta o frame
(`if timestamp <= 0 || ... < self.seekTime { return }`). Dependendo da ordem de visibilidade
entre as escritas, um frame que deveria ser descartado (por ser anterior ao ponto de seek)
pode escapar para a fila de saída — o usuário vê um frame do ponto errado do vídeo por um
instante após o seek.

---

## 6. `currentRender`/`currentRenderReadOffset`/`sourceNodeAudioFormat` compartilhados entre a thread de render de áudio em tempo real e a main thread

**Arquivos:**
`Sources/KSPlayer/MEPlayer/AudioEnginePlayer.swift` (linhas 105–123, 228–234, 268–311)
`Sources/KSPlayer/MEPlayer/AudioGraphPlayer.swift` (linhas 18–32, 204–209, 246–289)
`Sources/KSPlayer/MEPlayer/AudioUnitPlayer.swift` (linhas 14–24, 97–102, 136–175)
**Severidade:** critica

Nas três implementações de `AudioOutput`, `currentRender` (um `AudioFrame?`),
`currentRenderReadOffset` e `sourceNodeAudioFormat` são lidos e escritos dentro de
`audioPlayerShouldInputData`/`audioPlayerDidRenderSample`, que rodam **na thread de render em
tempo real do Core Audio** (callback de `AVAudioSourceNode`/`AURenderCallback`,
`AudioUnitAddRenderNotify`). Ao mesmo tempo, `flush()` (que faz `currentRender = nil`) é
chamado a partir da **main thread** em vários pontos: `KSMEPlayer.seek(time:completion:)` (a
completion roda via `DispatchQueue.main.async` dentro de `MEPlayerItem.readThread()`),
`KSMEPlayer.replace(url:options:)` e `audioRouteChange` (notificação do sistema). Nenhuma
dessas duas vias usa lock/queue de serialização em comum.

**Cenário concreto de falha:** o usuário dá um seek durante a reprodução. A main thread executa
`audioOutput.flush()` → `currentRender = nil`, liberando a referência forte ao `AudioFrame`
atual, exatamente no instante em que a thread de render está no meio de
`currentRender = renderSource?.getAudioOutputRender()` (uma leitura-modificação-escrita não
atômica sobre a mesma stored property). Escrita concorrente de uma propriedade de tipo classe
via ARC sem sincronização é uma data race clássica: a sequência retain/release do setter pode
intercalar entre as duas threads e resultar em release duplicado do `AudioFrame` antigo
(over-release) — nesse fork isso se manifesta como uma queda esporádica do processo de áudio
(crash) justamente em seeks feitos durante playback, difícil de reproduzir de forma
determinística por depender do timing exato do callback de render.

---

## 7. `options.audioFilters`/`options.videoFilters` mutados na main thread enquanto são lidos por frame na thread de decode

**Arquivos:**
`Sources/KSPlayer/MEPlayer/Filter.swift` (linhas 105–114, chamado por frame)
`Sources/KSPlayer/MEPlayer/KSMEPlayer.swift` (linhas 78–93, `playbackRate` `didSet`)
**Severidade:** critica

`MEFilter.filter(options:inputFrame:completionHandler:)` é chamado **para cada frame decodificado**
(dentro do loop `avcodec_receive_frame` em `FFmpegDecode.decodeFrame`, ver
`Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:137`), e lê `options.audioFilters.joined(separator:)`
ou faz `options.videoFilters.append("idet")` — sempre na thread de decode. Já
`KSMEPlayer.playbackRate` (linhas 78–93), setado tipicamente pela UI (ex.: mudança de velocidade
de reprodução pelo controle remoto), reatribui todo o array: `options.audioFilters = audioFilters`
na main thread, sem qualquer sincronização com a thread de decode.

**Cenário concreto de falha:** o usuário está assistindo e muda a velocidade de reprodução (2x).
`KSMEPlayer.playbackRate.didSet` roda na main thread e reatribui `options.audioFilters` (um
`[String]`, cujo buffer interno é copy-on-write e tem contagem de referência gerenciada por ARC)
no exato momento em que a thread de decode de áudio está iterando `options.audioFilters.joined(...)`
para montar a string de filtros do próximo frame. Mutação e leitura concorrentes do mesmo buffer
COW sem lock podem corromper a contagem de referência do array e derrubar o processo — e, ao
contrário dos outros achados, este é acionado por uma ação de UI comum (trocar velocidade) que
ocorre dezenas de vezes por segundo do lado do decode (uma vez por frame), tornando a janela de
corrida muito mais fácil de atingir na prática do que os demais.

---

## 8. `AudioDescriptor.audioFormat`/`outChannel` mutados por notificação do sistema enquanto o resampler os lê/escreve na thread de decode

**Arquivos:**
`Sources/KSPlayer/MEPlayer/Resample.swift` (linhas 271–277, 376–383; `AudioSwresample.setup`, linha 234)
`Sources/KSPlayer/MEPlayer/KSMEPlayer.swift` (linhas 168–173 `spatialCapabilityChange`, 176–189 `audioRouteChange`)
**Severidade:** alta

`updateAudioFormat()` (linhas 376–383 de `Resample.swift`) reatribui `audioFormat` e `outChannel`
de um `AudioDescriptor` compartilhado. Ele é chamado a partir de `KSMEPlayer.spatialCapabilityChange`
(observer de `AVAudioSession.spatialPlaybackCapabilitiesChangedNotification`) e
`audioRouteChange` (observer de `AVAudioSession.routeChangeNotification`) — notificações do
`AVAudioSession` que o `NotificationCenter` entrega na thread em que foram postadas, tipicamente
uma thread interna de áudio do sistema, **não** a main thread. Ao mesmo tempo,
`AudioSwresample.setup(descriptor:)` (linha 234, chamado na thread de decode a cada troca de
formato do frame de entrada) lê e escreve `descriptor.outChannel`/`descriptor.channel`/
`descriptor.audioFormat` do mesmo objeto `AudioDescriptor` (ele é o mesmo compartilhado via
`FFmpegAssetTrack.audioDescriptor`), passando `&descriptor.outChannel` por referência direta para
`swr_alloc_set_opts2` (API C do FFmpeg).

**Cenário concreto de falha:** o usuário conecta/desconecta um alto-falante Bluetooth/AirPlay
durante a reprodução, disparando `audioRouteChange` numa thread de áudio do sistema, que chama
`updateAudioFormat()` e começa a reescrever `outChannel` (uma struct `AVChannelLayout` que pode
conter ponteiros internos para layouts customizados) exatamente enquanto a thread de decode está
no meio de `swr_alloc_set_opts2(&swrContext, &descriptor.outChannel, ...)`. A API C do FFmpeg pode
receber uma struct "rasgada" (parcialmente atualizada), com um ponteiro de uma versão do layout e
campos de contagem de canais de outra — um cenário de memória inválida sendo repassado para código
C, não apenas uma inconsistência lógica.

---

## 9. `CircularBuffer.count` lido sem lock enquanto `push`/`pop` mutam os índices sob lock

**Arquivo:** `Sources/KSPlayer/MEPlayer/CircularBuffer.swift` (linhas 21–28)
**Severidade:** media

```swift
@inline(__always)
public var count: Int {
//        condition.lock()
//        defer { condition.unlock() }
    Int(tailIndex &- headIndex)
}
```

O próprio código mostra que o lock foi deliberadamente comentado (por performance), mas
`headIndex`/`tailIndex` continuam sendo mutados sob `condition.lock()` dentro de `push`/`pop`/`flush`
(chamados da thread produtora — leitura/decode — e da thread consumidora — render). `count` é a
base de `packetCount`/`frameCount` em `SyncPlayerItemTrack`/`AsyncPlayerItemTrack`, usados por
`MEPlayerItem.codecDidChangeCapacity()` (na main thread, via timer) para decidir buffering e
bitrate adaptativo.

**Cenário concreto de falha:** durante alta contenção (leitura enfileirando pacotes rapidamente
enquanto o render consome), a main thread lê `videoTrack.frameCount`/`packetCount` sem lock no
mesmo instante em que a thread de decode está no meio de `pop()` atualizando `headIndex` sob lock.
O valor de `count` pode ficar momentaneamente inconsistente (refletindo um estado intermediário
dessincronizado de `head`/`tail` em relação ao buffer real), levando `options.playable(capacitys:)`
a tomar uma decisão de buffering baseada em uma contagem estale — na pior hipótese, disparando
`pause()`/`resume()` a mais ou a menos do que deveria.

---

## 10. (Somente macOS) `CADisplayLink` customizado: `runloop`/`mode` lidos na thread do `CVDisplayLink`, escritos na main thread

**Arquivo:** `Sources/KSPlayer/MEPlayer/MetalPlayView.swift` (linhas 368–445; leitura em 414–418,
escrita em 433–436 e 438–444)
**Severidade:** baixa

No `#if os(macOS)`, a classe `CADisplayLink` própria embrulha `CVDisplayLink`. O callback de
`CVDisplayLinkSetOutputHandler` roda numa thread interna do `CVDisplayLink` e lê
`self.runloop`/`self.mode` (linha 416) para agendar o `perform(_:target:argument:order:modes:)`
no run loop principal. `add(to:forMode:)` e `invalidate()` escrevem essas mesmas propriedades a
partir da main thread (chamado por `KSMEPlayer.videoOutput`'s `didSet` → `oldValue?.invalidate()`),
sem qualquer lock.

**Cenário concreto de falha:** ao trocar de `videoOutput` (ex.: troca de player) a main thread
chama `invalidate()`, que zera `runloop` (`runloop = nil`), no exato instante em que o callback do
`CVDisplayLink` (thread própria) está lendo `self.runloop?.perform(...)`. Na pior janela, o
`perform` pode ser despachado para um run loop que está no meio de ser desreferenciado, ou o frame
simplesmente é perdido (menor impacto, restrito a macOS).

---

## Resumo por severidade

| # | Achado | Severidade |
|---|--------|------------|
| 4 | `decoderMap` mutado por callback do VideoToolbox + thread de decode | critica |
| 6 | `currentRender` dos `AudioOutput` entre render thread e main thread | critica |
| 7 | `options.audioFilters`/`videoFilters` entre `playbackRate` (main) e Filter (decode) | critica |
| 1 | `NSCondition` usado sem `lock()/unlock()` | alta |
| 2 | `state`/`seekTime` de `MEPlayerItem` sem sincronização entre main e read thread | alta |
| 5 | `seekTime`/`state` de `SyncPlayerItemTrack` entre decode/VT callback/read/main | alta |
| 8 | `AudioDescriptor.updateAudioFormat()` vs `AudioSwresample` na thread de decode | alta |
| 3 | `FFmpegAssetTrack.isEnabled` em `select(track:)` vs `reading()` | media |
| 9 | `CircularBuffer.count` lido sem lock | media |
| 10 | `CADisplayLink` (macOS) `runloop`/`mode` sem lock | baixa |
