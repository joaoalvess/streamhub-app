# Auditoria de gestão de memória — KSPlayer (fork StreamHub)

Escopo: `Sources/` do fork GPL do KSPlayer. Foco: retain cycles em closures/delegates,
buffers FFmpeg (`AVPacket`/`AVFrame`/`AVCodecContext`/`SwsContext`/`SwrContext`) não
liberados, `CVPixelBuffer`/`CMSampleBuffer` vazando, e observers (`NotificationCenter`,
KVO) não removidos. Motivado pela issue conhecida do upstream: memory leaks ao
reproduzir mp4 (#626).

Cada finding foi confirmado lendo o código (arquivo/linha citados); quando o
comportamento depende de semântica do FFmpeg (ownership de buffers `av_malloc`/
`av_buffer_ref`), verifiquei contra os comentários/contratos documentados no próprio
código e o uso equivalente em outros pontos do arquivo.

---

## 1. [CRÍTICA] `SyncPlayerItemTrack.shutdown()` nunca libera os decoders FFmpeg — leak de `AVCodecContext`/`AVFrame`/`SwsContext` em todo vídeo com legenda embutida

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift:24-110` (classe `SyncPlayerItemTrack`, `decoderMap` na linha 27, `shutdown()` nas linhas 104-110)

```swift
fileprivate var decoderMap = [Int32: DecodeProtocol]()
...
func shutdown() {
    if state == .idle {
        return
    }
    state = .closed
    outputRenderQueue.shutdown()
}
```

Compare com `AsyncPlayerItemTrack.decodeThread()` (linhas 233-261), que é a única rotina
em todo o arquivo que efetivamente libera os decoders:

```swift
case .finished, .closed, .failed:
    decoderMap.values.forEach { $0.shutdown() }
    decoderMap.removeAll()
    break outerLoop
```

`AsyncPlayerItemTrack.shutdown()` (linhas 272-278) apenas chama `super.shutdown()` e
depende dessa thread de decode (`decodeThread`) estar rodando para eventualmente notar
`state == .closed` e limpar o `decoderMap`. **`SyncPlayerItemTrack` não tem essa thread**
— ela decodifica de forma síncrona dentro de `putPacket`/`doDecode` — então o
`decoderMap` dela nunca é esvaziado e `DecodeProtocol.shutdown()` (que libera
`avcodec_free_context`, `av_frame_free`, `sws_freeContext` — ver `FFmpegDecode.swift:194-198`
e `SubtitleDecode.swift:80-87`) **nunca é chamado**. Não há `deinit` em nenhuma dessas
classes (`SyncPlayerItemTrack`, `FFmpegDecode`, `SubtitleDecode`), então quando o objeto
Swift é desalocado pelo ARC, a memória C (contexto do codec, frame, contexto de scale)
não é liberada — fica vazada até o processo terminar.

**Por que isso acontece em praticamente todo mp4 com legenda embutida:** as faixas de
legenda **sempre** usam `SyncPlayerItemTrack<SubtitleFrame>`, nunca `AsyncPlayerItemTrack`
— veja `MEPlayerItem.createCodec()`:

```swift
// Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:339-343
if assetTrack.mediaType == .subtitle {
    let subtitle = SyncPlayerItemTrack<SubtitleFrame>(mediaType: .subtitle, frameCapacity: 255, options: options)
    assetTrack.subtitle = subtitle
    allPlayerItemTracks.append(subtitle)
}
```

E faixas de legenda em texto (SRT/mov_text/ASS/WebVTT — o formato mais comum em mp4/mkv
baixados) vêm **habilitadas por padrão**, sem qualquer ação do usuário — ver
`FFmpegAssetTrack.swift:117-118`:

```swift
if mediaType == .subtitle {
    isEnabled = !isImageSubtitle || stream.pointee.disposition & AV_DISPOSITION_FORCED == AV_DISPOSITION_FORCED
}
```

Isso quer dizer: sempre que `first.isEnabled` for `true` para a faixa de legenda em
`MEPlayerItem.reading()` (linha 552), os pacotes de legenda são enviados a essa
`SyncPlayerItemTrack`, que aloca um `SubtitleDecode` (com seu próprio `AVCodecContext` via
`avcodec_alloc_context3` e um `VideoSwresample` interno com `sws_getContext` para legendas
bitmap) inserido em `decoderMap`. Isso acontece automaticamente, sem seleção manual de
legenda.

**Cenário concreto de falha:** o usuário assiste, no StreamHub, um mp4 com faixa de
legenda embutida (comum em rips/downloads). `KSMEPlayer.shutdown()` →
`playerItem.shutdown()` → `allPlayerItemTracks.forEach { $0.shutdown() }` roda o
`shutdown()` acima, que **não libera nada relativo ao decoder de legenda**. Ao trocar de
título (`replace(url:)`) ou fechar o player, o `AVCodecContext` e o `SwsContext` alocados
para aquela legenda ficam retidos para sempre no heap nativo. Repita para cada vídeo
assistido na sessão do app e o processo acumula memória nativa continuamente — esse é o
padrão relatado na issue upstream #626 ("memory leak playing mp4"). O mesmo problema
também afeta faixas de vídeo/áudio quando `options.syncDecodeVideo`/`syncDecodeAudio`
estão habilitados (`MEPlayerItem.swift:379,412`), e a faixa de closed captions (EIA-608)
criada em `FFmpegDecode.swift:51` (que nem chega a entrar em `allPlayerItemTracks`, então
seu `shutdown()` jamais é chamado por ninguém, nem mesmo o incompleto acima).

**Correção sugerida:** em `SyncPlayerItemTrack.shutdown()`, adicionar
`decoderMap.values.forEach { $0.shutdown() }; decoderMap.removeAll()` (mesma lógica já
usada em `AsyncPlayerItemTrack.decodeThread()`).

---

## 2. [CRÍTICA] `VideoToolboxDecode` vaza o buffer `av_malloc`'d de `avio_close_dyn_buf` em todo frame convertido — cresce a cada frame decodificado

**Arquivo:** `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:160-199`

```swift
fileprivate func getSampleBuffer(isConvertNALSize: Bool, data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
    if isConvertNALSize {
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        let status = avio_open_dyn_buf(&ioContext)
        if status == 0 {
            ...
            var demuxBuffer: UnsafeMutablePointer<UInt8>?
            let demuxSze = avio_close_dyn_buf(ioContext, &demuxBuffer)
            return try createSampleBuffer(data: demuxBuffer, size: Int(demuxSze))
        }
        ...
    }
    ...
}

private func createSampleBuffer(data: UnsafeMutablePointer<UInt8>?, size: Int) throws -> CMSampleBuffer {
    var blockBuffer: CMBlockBuffer?
    var sampleBuffer: CMSampleBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: size, blockAllocator: kCFAllocatorNull, ...)
    ...
}
```

`avio_close_dyn_buf` devolve um buffer alocado por `av_malloc` cuja liberação é
responsabilidade explícita de quem chamou (contrato documentado no header do FFmpeg:
"The buffer must be freed by the caller"). Aqui esse buffer (`demuxBuffer`) é passado
para `CMBlockBufferCreateWithMemoryBlock` com `blockAllocator: kCFAllocatorNull` — o que
diz explicitamente ao Core Media para **não** liberar essa memória quando o
`CMBlockBuffer`/`CMSampleBuffer` for destruído. Em nenhum lugar do arquivo (nem de todo o
`Sources/`, confirmado por busca por `av_free(`) existe uma chamada a `av_free(demuxBuffer)`
depois de usá-lo. O resultado é que o buffer nativo alocado por `avio_open_dyn_buf`/
`avio_close_dyn_buf` fica permanentemente vazado a cada chamada a `getSampleBuffer` com
`isConvertNALSize == true`.

`isConvertNALSize` é decidido uma vez por faixa em `FFmpegAssetTrack.swift:186-193`:

```swift
if extradataSize >= 5, extradata[4] == 0xFE {
    extradata[4] = 0xFF
    isConvertNALSize = true
}
```

Esse é o ajuste conhecido para arquivos H.264/HEVC com `length_size_minus_one`
não-padrão no `avcC` (byte 4 do extradata = `0xFE`), algo real em certos remuxes/mp4
"quebrados". Quando essa condição é verdadeira, **todo frame decodificado** passa por
`getSampleBuffer(isConvertNALSize: true, ...)` em `VideoToolboxDecode.decodeFrame`
(linha 41), ou seja, o vazamento cresce linearmente com o tempo de reprodução — não é um
leak único por sessão, é por frame (a 24-60 fps).

**Cenário concreto de falha:** reproduzir, com decodificação por hardware
(VideoToolbox) habilitada (padrão), um mp4/mov cujo H.264/HEVC tenha esse extradata
não-padrão. A cada frame decodificado, um novo buffer nativo do tamanho do NAL
convertido é alocado e nunca liberado — memória residente do processo cresce
continuamente durante a reprodução, exatamente o sintoma relatado em "memory leak
playing mp4".

**Correção sugerida:** liberar `demuxBuffer` com `av_free(demuxBuffer)` após o
`CMBlockBufferCreateWithMemoryBlock` copiar/reter os dados (ou usar um
`blockAllocator` que chame `av_free` como callback de liberação, em vez de
`kCFAllocatorNull`).

---

## 3. [ALTA] `ThumbnailController.getPeeks` reutiliza um único `AVPacket` sem `av_packet_unref` entre leituras — vaza um buffer de pacote por leitura descartada

**Arquivo:** `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:85-131`

```swift
var packet = AVPacket()
...
for i in 0 ..< thumbnailCount {
    ...
    while av_read_frame(formatCtx, &packet) >= 0 {
        if packet.stream_index == Int32(videoStreamIndex) {
            if avcodec_send_packet(codecContext, &packet) < 0 {
                break
            }
            ...
            break
        }
        // <- nenhum av_packet_unref(&packet) aqui antes do próximo av_read_frame
    }
}
av_packet_unref(&packet)   // só uma vez, depois de TODAS as thumbnailCount iterações
reScale.shutdown()
```

Diferente do restante do player (que usa a classe `Packet` — `Model.swift:195-229 —`
cujo `deinit` chama `av_packet_unref`/`av_packet_free`), aqui o `AVPacket` é uma struct
na stack, reutilizada chamada após chamada de `av_read_frame`. Cada `av_read_frame`
bem-sucedido preenche `packet` com uma nova referência (`buf`) para o buffer de dados —
sem um `av_packet_unref(&packet)` **antes** da próxima chamada, a referência anterior é
simplesmente sobrescrita, e o `AVBufferRef` que ela apontava nunca tem seu contador de
referência decrementado (o dono anterior "some" sem nunca liberar sua contagem). Isso
acontece:

- para **todo pacote de outra stream** (áudio, legenda) lido enquanto se procura o
  próximo frame de vídeo após cada seek — comum, já que a maioria dos contêineres
  intercala áudio/vídeo;
- para o próprio pacote de vídeo processado em cada iteração do `for`, já que o
  `break` que sai do laço interno acontece sem unref, e o único `av_packet_unref` do
  método só roda **depois** que todas as `thumbnailCount` (padrão 100) iterações do
  `for` externo terminam.

**Cenário concreto de falha:** gerar thumbnails de scrubbing para a barra de progresso
(`ThumbnailController.generateThumbnail(for:thumbWidth:)`) em qualquer vídeo do
StreamHub. Com o padrão de 100 thumbnails e um contêiner com faixas de áudio/legenda
intercaladas, cada chamada a `generateThumbnail` pode vazar potencialmente centenas de
buffers de pacote (um por `av_read_frame` cuja referência é descartada sem unref) — só
o último pacote lido em toda a função é liberado.

**Correção sugerida:** chamar `av_packet_unref(&packet)` no fim de cada iteração do
`while` (tanto no caminho "pacote de vídeo processado" quanto no "pacote ignorado"),
antes de repetir o `av_read_frame`.

---

## 4. [MÉDIA] `KSAVPlayer.observer(playerItem:)` remove observers do `NotificationCenter` usando o item novo em vez do antigo — registro do item anterior nunca é removido

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSAVPlayer.swift:218-222, 300-341`

```swift
itemObservation = player.observe(\.currentItem) { [weak self] player, _ in
    guard let self else { return }
    self.observer(playerItem: player.currentItem)   // já é o item NOVO
}
...
private func observer(playerItem: AVPlayerItem?) {
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
    ...
    guard let playerItem else { return }
    NotificationCenter.default.addObserver(self, selector: #selector(moviePlayDidEnd), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
    NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEndTime), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
    ...
}
```

`observer(playerItem:)` é chamado pela KVO de `\.currentItem` já com o **novo**
`AVPlayerItem` (o KVO dispara depois da troca). As duas chamadas a `removeObserver(...,
object: playerItem)` no topo da função tentam remover um registro filtrado pelo item
**novo** — mas o registro que precisa ser removido é o do item **antigo** (adicionado na
chamada anterior desta mesma função, quando esse item ainda era "o novo"). Como
`object:` no `NotificationCenter` funciona como filtro exato, essas duas chamadas de
`removeObserver` são, na prática, sempre no-ops (nunca existiu um registro para
`(self, name, object: <item novo>)` antes de as `addObserver` seguintes o criarem). O
registro do item antigo simplesmente nunca é removido.

**Cenário concreto de falha:** qualquer sequência de reprodução que troque de vídeo no
mesmo `KSAVPlayer` — `replace(url:options:)` (`KSAVPlayer.swift:448`) ou apenas o
`AVQueuePlayer` avançando para o próximo item — dispara a KVO de `currentItem` e chama
`observer(playerItem:)` de novo. A cada troca, mais um par de registros de
`.AVPlayerItemDidPlayToEndTime`/`.AVPlayerItemFailedToPlayToEndTime` (filtrados pelo
`AVPlayerItem` já descartado) fica acumulado na tabela interna do
`NotificationCenter.default`, preso por toda a vida do `KSAVPlayer` — numa sessão longa
trocando de título repetidamente (um app tvOS de streaming, o caso de uso do
StreamHub), esses registros crescem sem limite e só são liberados quando o próprio
`KSAVPlayer` é desalocado.

**Correção sugerida:** capturar o `AVPlayerItem` antigo (via `[.old]` na KVO, ou
guardando o valor anterior em uma propriedade) e usar **esse** valor nas chamadas de
`removeObserver`, não o `playerItem` recém-chegado.

---

## 5. [MÉDIA] `MEPlayerItem`/`AbstractAVIOContext`: `Unmanaged.passRetained(self)` do IO customizado não é liberado se `avformat_open_input` falhar

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:190-213, 639-648, 862-881`

```swift
// getContext() — Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:862-881
extension AbstractAVIOContext {
    func getContext() -> UnsafeMutablePointer<AVIOContext> {
        avio_alloc_context(av_malloc(Int(bufferSize)), bufferSize, writable ? 1 : 0, Unmanaged.passRetained(self).toOpaque()) { ... }
        ...
    }
}
```

```swift
// openThread() — MEPlayerItem.swift:190-213
if let pb = options.process(url: url) {
    formatCtx.pointee.pb = pb.getContext()   // passRetained(self) acontece aqui dentro
}
...
var result = avformat_open_input(&self.formatCtx, urlString, nil, &avOptions)
...
guard result == 0 else {
    error = .init(errorCode: .formatOpenInput, avErrorCode: result)
    avformat_close_input(&self.formatCtx)     // formatCtx vira nil AQUI
    return
}
```

```swift
// shutdown() — MEPlayerItem.swift:639-648
if let formatCtx = self.formatCtx, (formatCtx.pointee.flags & AVFMT_FLAG_CUSTOM_IO) != 0, let opaque = formatCtx.pointee.pb.pointee.opaque {
    let value = Unmanaged<AbstractAVIOContext>.fromOpaque(opaque).takeRetainedValue()
    value.close()
}
```

Quando o app usa um protocolo customizado (subclasse de `KSOptions` que sobrescreve
`process(url:)` — o hook existe justamente para isso, ex.: fontes de dados embutidas),
`getContext()` faz um `Unmanaged.passRetained(self)` — um +1 de retain que só é
balanceado pelo `takeRetainedValue()` em `shutdown()`. Esse balanceamento só roda se, no
momento do `shutdown()`, **`self.formatCtx` ainda não for `nil`** e tiver a flag
`AVFMT_FLAG_CUSTOM_IO`. Mas no caminho de erro do `openThread()` (`avformat_open_input`
retornando falha), o código já chama `avformat_close_input(&self.formatCtx)`
imediatamente, zerando `formatCtx` **antes** de `shutdown()` ser chamado. Quando
`shutdown()` roda depois (disparado por `sourceDidFailed` no player), `self.formatCtx`
já é `nil` — o `if let formatCtx = self.formatCtx` falha, o `takeRetainedValue()` nunca
executa, e o objeto `AbstractAVIOContext` customizado (retido via `passRetained`) fica
permanentemente vazado (nunca chega a ser liberado nem seu `.close()` chamado).

**Cenário concreto de falha:** usar um `AbstractAVIOContext` customizado (protocolo de
dados próprio) para abrir uma URL que falha em `avformat_open_input` (arquivo
corrompido, protocolo indisponível, timeout de rede tratado como erro de abertura) — o
objeto Swift que implementa a leitura customizada (e qualquer buffer/socket que ele
segure) vaza a cada tentativa de abertura falha.

**Correção sugerida:** também liberar/fechar o `AbstractAVIOContext` retido no próprio
branch de erro do `openThread()` (antes ou junto do `avformat_close_input` de
linha 211), não só no `shutdown()`.

---

## Resumo

| # | Severidade | Arquivo | Vazamento |
|---|---|---|---|
| 1 | Crítica | `MEPlayerItemTrack.swift` (`SyncPlayerItemTrack.shutdown`) | `AVCodecContext`/`AVFrame`/`SwsContext` de todo decoder síncrono (legendas embutidas por padrão, closed captions, e vídeo/áudio quando `syncDecodeVideo/Audio` ativos) |
| 2 | Crítica | `VideoToolboxDecode.swift` (`getSampleBuffer`) | buffer `av_malloc` por frame quando `isConvertNALSize == true` (extradata H.264/HEVC não-padrão) |
| 3 | Alta | `ThumbnailController.swift` (`getPeeks`) | buffer de `AVPacket` por leitura descartada durante geração de thumbnails |
| 4 | Média | `KSAVPlayer.swift` (`observer(playerItem:)`) | registro de `NotificationCenter` do `AVPlayerItem` anterior, a cada troca de vídeo |
| 5 | Média | `MEPlayerItem.swift` (`getContext`/`openThread`/`shutdown`) | `AbstractAVIOContext` customizado retido via `Unmanaged.passRetained`, quando `avformat_open_input` falha |
