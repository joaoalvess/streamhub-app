# Auditoria de performance — KSPlayer (fork StreamHub)

Escopo: `Sources/` do fork GPL do KSPlayer. Foco: cópias de buffer desnecessárias,
alocação dentro de loops de render/decode, trabalho pesado na main thread, locks em
caminhos quentes, conversões de pixel format evitáveis.

Cada finding foi confirmado lendo o código (arquivo/linha citados) e seguindo a cadeia
de chamadas real até o hot path (display link → draw, decode → filter → resample).
Não reporto nada que dependa só de leitura superficial ou hipótese — só o que dá para
sustentar com a chamada concreta e o cenário de disparo.

---

## 1. [CRÍTICA] `MetalRender.draw` bloqueia a main thread esperando a GPU terminar, em todo frame do caminho Metal

**Arquivo:** `Sources/KSPlayer/Metal/MetalRender.swift:92-114` (método `draw(pixelBuffer:display:drawable:)`, `@MainActor`)

```swift
@MainActor
func draw(pixelBuffer: PixelBufferProtocol, display: DisplayEnum = .plane, drawable: CAMetalDrawable) {
    ...
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()   // <-- bloqueia a main thread até a GPU acabar
}
```

`draw` é `@MainActor` e é chamado a partir de `MetalView.draw(pixelBuffer:display:size:)`
(`Sources/KSPlayer/MEPlayer/MetalPlayView.swift:274-301`), que por sua vez é chamado de
`MetalPlayView.draw(force:)` (linha 218), disparado pelo `CADisplayLink` **na main
run loop** (`displayLink.add(to: .main, forMode: .common)`, linha 82). Ou seja: todo
frame renderizado por esse caminho faz `commit()` e então `waitUntilCompleted()`
**na main thread**, travando-a pelo tempo inteiro que a GPU leva para render+present
daquele frame. Isso anula qualquer pipelining (double/triple buffering) do Metal e
qualquer interação de UI (troca de faixa, OSD, scroll de menu) fica presa atrás do
tempo de GPU do frame anterior.

`clear(drawable:)` (linhas 78-90) tem o mesmo padrão, mas é chamado raramente (só ao
trocar de camada), então o impacto ali é bem menor.

**Quando esse caminho dispara de verdade:** `MetalPlayView.draw(force:)` só usa
`AVSampleBufferDisplayLayer` (que não passa por `MetalRender`) quando
`options.isUseDisplayLayer()` é `true` **e** `pixelBuffer.cvPixelBuffer != nil`
(`MetalPlayView.swift:185`). `isUseDisplayLayer()` (`KSOptions.swift:256-258`) só é
`true` quando `display == .plane`. Isso significa que o caminho Metal síncrono acima
é usado sempre que:
- o modo de exibição é VR/VRBox (360°/imersivo, linhas do `DisplayEnum`), **ou**
- o frame decodificado não é um `CVPixelBuffer` "de verdade" — que é exatamente o caso
  da classe `PixelBuffer` (`cvPixelBuffer` sempre `nil`, ver finding #3), usada para
  formatos 10-bit em decode via software (ex.: fallback de Dolby Vision perfil 7, ou
  qualquer fonte 10-bit sem aceleração de hardware disponível).

Ambos os cenários são relevantes para o objetivo de paridade com Infuse (360°/VR e
HDR/DoVi com fallback por software), então o stall de main thread por frame é real,
não só teórico.

**Cenário concreto de falha:** reproduzir um remux 4K com Dolby Vision perfil 7 (comum
em rips de UHD Blu-ray) força fallback por software em algum ponto → frames passam por
`PixelBuffer` → `isUseDisplayLayer()` falha → todo frame renderizado trava a main thread
pelo tempo de composição da GPU, causando soluços de UI e possível acúmulo de frames
atrasados na fila de decode.

**Sugestão de direção (sem aplicar):** remover o `waitUntilCompleted()` do caminho
comum e usar um `MTLSharedEvent`/completion handler para sinalizar quando o drawable
pode ser reciclado, deixando o `commit()` assíncrono como é o padrão recomendado pela
Apple para pipelines de vídeo.

---

## 2. [ALTA] `MEFilter.filter()` vaza um `AVBufferRef` a cada frame quando há `hw_frames_ctx`, e o "cache" que evita reconstruir o grafo nunca considera esse buffer

**Arquivo:** `Sources/KSPlayer/MEPlayer/Filter.swift:105-149`, especificamente linhas
126-133

```swift
var params = AVBufferSrcParameters()
params.format = inputFrame.pointee.format
...
if let ctx = inputFrame.pointee.hw_frames_ctx {
    params.hw_frames_ctx = av_buffer_ref(ctx)     // incrementa refcount, aloca um novo AVBufferRef
}
...
if self.params != params || self.filters != filters {
    self.params = params
    self.filters = filters
    if !setup(filters: filters) { ... }
}
// se a comparação abaixo bate (caso comum: mesma resolução/formato do frame anterior),
// o `params` local (com o av_buffer_ref recém-criado) é descartado aqui sem av_buffer_unref
```

O operador `==` usado na comparação (`AVBufferSrcParameters: Equatable` em
`Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:385-388`) compara `format`, `width`,
`height`, `sample_aspect_ratio`, `sample_rate` e `ch_layout` — **nunca `hw_frames_ctx`**.
Isso quer dizer que, para o caso comum (mesmo vídeo, mesma resolução frame a frame), a
comparação dá igual e o bloco `if` não executa: o `av_buffer_ref` que acabou de ser
criado na linha 127 fica em uma variável local `var params` que sai de escopo sem que
`av_buffer_unref` seja chamado em lugar nenhum — busquei em todo o `Sources/` e não há
nenhum `av_buffer_unref` correspondente (`rg av_buffer_unref` só aparece comentado em
`AVFFmpegExtension.swift:44`). Mesmo quando a comparação dá diferente (primeiro frame,
mudança de resolução) e `self.params = params` executa, o `AVBufferRef` **anterior**
que estava em `self.params.hw_frames_ctx` (se havia) é sobrescrito e perdido, também
sem unref.

Ou seja: toda vez que essa função roda com `inputFrame.pointee.hw_frames_ctx != nil`,
um `AVBufferRef` é vazado — na prática, **todo frame**, já que o descarte acontece tanto
no ramo "igual" quanto no ramo "diferente".

**Quando `hw_frames_ctx` fica populado:** `FFmpegDecode` (usado quando
`options.hardwareDecode` está ligado mas a criação da `DecompressionSession` própria
falha — `SyncPlayerItemTrack.makeDecode`, `MEPlayerItemTrack.swift:301-315`) configura
`codecContext.getFormat()` (`AVFFmpegExtension.swift:19-55`), que registra
`hw_device_ctx = AV_HWDEVICE_TYPE_VIDEOTOOLBOX` no codec context. Quando o libavcodec
negocia o hwaccel do VideoToolbox internamente a partir disso, os `AVFrame` decodificados
saem com `hw_frames_ctx` preenchido automaticamente (comportamento padrão do hwaccel
genérico do FFmpeg) — e isso é justamente o caso tratado em
`VideoSwresample.change()` (`Resample.swift:88-89`,
`if avframe.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue`).

**Cenário concreto de falha:** vídeo com decode acelerado por hardware que caiu no
fallback via `FFmpegDecode` (por exemplo, `DecompressionSession` falhou ao criar) **e**
algum filtro de vídeo ativo (`autoDeInterlace`, auto-rotate que empurra `transpose`/
`hflip`/`vflip`/`rotate` em `MEPlayerItem.createCodec` linhas 363-374, ou qualquer
filtro custom) — cada frame decodificado vaza um `AVBufferRef`. Em uma sessão de
playback longa (filme de 2h a 24fps = ~172.800 frames) isso é uma alocação C que nunca
é liberada por frame, crescendo o RSS do processo de forma constante até o fim da
reprodução; em tvOS, com memória bem mais limitada que iOS/macOS, isso é um caminho
plausível para jetsam por excesso de memória em sessões longas.

---

## 3. [ALTA] `PixelBuffer.init` aloca um `MTLBuffer` novo por plano em **todo frame**, sem pool — ao contrário do caminho `CVPixelBufferPool` usado no resto do código

**Arquivo:** `Sources/KSPlayer/Metal/PixelBufferProtocol.swift:187-243` (`PixelBuffer.init(frame:)`)

```swift
for i in 0 ..< planeCount {
    let alignment = MetalRender.device.minimumLinearTextureAlignment(for: formats[i])
    lineSize.append(bytesPerRow[i].alignment(value: alignment))
    let buffer: MTLBuffer?
    let size = lineSize[i]
    let byteCount = bytesPerRow[i]
    let height = heights[i]
    if byteCount == size {
        buffer = MetalRender.device.makeBuffer(bytes: bytes[i]!, length: height * size)   // aloca + copia
    } else {
        buffer = MetalRender.device.makeBuffer(length: heights[i] * lineSize[i])           // aloca
        ...                                                                                 // e copia linha a linha
    }
    buffers.append(buffer)
}
```

`PixelBuffer` é instanciado uma vez por frame decodificado sempre que
`VideoSwresample.transfer(frame:)` decide que o formato precisa de "left shift"
(`Resample.swift:124-126`: `if format.leftShift > 0 { return PixelBuffer(frame: frame) }`),
ou seja, para os formatos 10-bit `AV_PIX_FMT_YUV420P10LE/422P10LE/444P10LE` quando
chegam decodificados via software (sem VideoToolbox) — cenário real para fallback de
Dolby Vision perfil 7 e para fontes 10-bit sem aceleração de hardware disponível.

Diferente do caminho principal (`VideoSwresample.transfer(format:width:height:data:linesize:)`,
`Resample.swift:146-206`), que usa um **`CVPixelBufferPool` cacheado** (`pool` em
`Resample.swift:72,117`) e só recria o pool quando formato/dimensão mudam, `PixelBuffer`
não tem nenhum cache de `MTLBuffer` — cada frame aloca `planeCount` buffers novos
(`device.makeBuffer`, que envolve alocação de memória e, no pior caso — quando
`bytesPerRow != alinhamento`, linhas 229-237 —, um loop de `copyMemory` linha a linha
adicional por cima da alocação). Para 4K 10-bit isso é um `makeBuffer` de vários MB por
plano, por frame, sem reaproveitamento.

**Cenário concreto de falha:** reprodução de um filme 4K HDR10/DoVi P7 com fallback por
software gera, a cada frame (24-60x por segundo), 2-3 alocações de `MTLBuffer` (uma por
plano) do tamanho do frame inteiro — pressão de alocação/desalocação constante em vez
de reciclagem via pool, aumentando o custo de CPU por frame e a fragmentação de memória
GPU-compartilhada, especialmente sensível em tvOS (Apple TV HD/4K têm bem menos memória
e banda que um Mac).

---

## 4. [MÉDIA] `VRDisplayModel`/`VRBoxDisplayModel` alocam um `MTLBuffer` novo por frame (e por olho, no caso VRBox) só para subir uma matriz 4x4

**Arquivo:** `Sources/KSPlayer/Metal/DisplayModel.swift:263-269` (`VRDisplayModel.set`)
e `Sources/KSPlayer/Metal/DisplayModel.swift:286-297` (`VRBoxDisplayModel.set`)

```swift
override func set(encoder: MTLRenderCommandEncoder) {
    super.set(encoder: encoder)
    var matrix = modelViewProjectionMatrix * modelViewMatrix
    let matrixBuffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float4x4>.size)
    encoder.setVertexBuffer(matrixBuffer, offset: 0, index: 2)
    ...
}
```

`set(encoder:)` é chamado uma vez por frame renderizado em modo VR/VRBox
(`MetalRender.draw` → `display.set(encoder:)`, `MetalRender.swift:108`). No modo
`VRBoxDisplayModel` isso roda **duas vezes por frame** (uma por olho, linhas 290-297).
Cada chamada aloca um `MTLBuffer` novo de 64 bytes via `makeBuffer(bytes:length:)` só
para subir uma matriz 4x4 que muda a cada frame (rotação por sensor de movimento/touch).
Isso é exatamente o caso de uso que a Apple recomenda resolver com
`encoder.setVertexBytes(_:length:index:)` (dados < 4KB, sem alocação de `MTLBuffer`
persistente) — aqui, em vez disso, cada frame passa pelo caminho completo de alocação
de recurso Metal (`makeBuffer`) para depois descartar o buffer imediatamente após o
`drawIndexedPrimitives`.

**Cenário concreto de falha:** playback de vídeo 360°/VR em loop longo aloca e descarta
1-2 `MTLBuffer`s por frame só para a matriz de câmera, gerando churn de alocação no
driver Metal sem necessidade — mais perceptível em tvOS, onde o Apple TV é o único
dispositivo puramente controlado por Siri Remote/toque indireto e roda por horas em
apps de vídeo.

---

## 5. [BAIXA] Loop escalar de interleave de chroma byte-a-byte em `VideoSwresample.transfer(format:width:height:data:linesize:)`

**Arquivo:** `Sources/KSPlayer/MEPlayer/Resample.swift:176-191`

```swift
if bufferPlaneCount < planeCount, i + 2 == planeCount {
    var sourceU = data[i]!
    var sourceV = data[i + 1]!
    var k = 0
    while k < height {
        var j = 0
        while j < size {
            contents?.advanced(by: 2 * j).copyMemory(from: sourceU.advanced(by: j), byteCount: byteCount)
            contents?.advanced(by: 2 * j + byteCount).copyMemory(from: sourceV.advanced(by: j), byteCount: byteCount)
            j += byteCount
        }
        contents = contents?.advanced(by: bytesPerRow)
        sourceU = sourceU.advanced(by: size)
        sourceV = sourceV.advanced(by: size)
        k += 1
    }
}
```

Esse ramo (usado quando o `CVPixelBuffer` de destino tem menos planos que o formato de
origem — reempacotar 3 planos YUV planares em um destino semi-planar/entrelaçado) faz
uma chamada de `copyMemory` por componente de 1-2 bytes, para cada pixel de cada linha
de cada frame — em vez de um interleave vetorizado (ex.: `vImageConvert_*` do
Accelerate, que o próprio arquivo já importa via `CoreGraphics`/`Libswscale` em outros
pontos do projeto). O overhead de chamada de função por componente de cor, multiplicado
por milhões de pixels por frame e dezenas de frames por segundo, é evitável. Severidade
baixa porque esse ramo específico só é exercitado quando `bufferPlaneCount < planeCount`
(reempacotamento de planos), um subconjunto dos formatos tratados por essa função — mas
vale registrar porque é exatamente o tipo de conversão de pixel format que deveria ser
vetorizada.

---

## Observações menores (não elevadas a finding formal)

- `MEFilter.filter()` (`Filter.swift:105-114`) recalcula `options.videoFilters.joined(separator: ",")`
  (alocando uma nova `String`) em **todo frame de vídeo**, mesmo quando a lista de
  filtros não mudou — só para comparar com `self.filters` e decidir se reconstrói o
  grafo. Com `autoDeInterlace`/auto-rotate ativos (bem comuns), isso é uma alocação de
  string por frame que dava para cachear junto com a comparação de `params`.
- `AudioFrame.init` (`Model.swift:254-261`) aloca um novo `UnsafeMutablePointer<UInt8>`
  por canal a cada frame de áudio decodificado — esperado dado o design atual (frames
  são objetos de fila, não hosts reaproveitados), mas é candidato a pool de buffers se
  o objetivo for eliminar toda alocação do hot path de áudio.
