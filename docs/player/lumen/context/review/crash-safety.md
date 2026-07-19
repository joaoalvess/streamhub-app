# Auditoria de crash-safety — KSPlayer fork

Escopo: `Sources/` (KSPlayer + DisplayCriteria). Foco: force unwraps perigosos, `try!`,
force casts, acesso a índices sem bounds check, unsafe pointers na interop com FFmpeg/C
sem validação de tamanho/nulidade, `precondition`/`fatalError` em caminhos alcançáveis.

Metodologia: leitura completa dos arquivos de `Sources/KSPlayer/{MEPlayer,AVPlayer,Metal,
Subtitle,Video,Core,SwiftUI}` e grep dirigido por `as!`, `try!`, `fatalError`,
`precondition`, `.pointee`, `UnsafeMutablePointer`, `bindMemory`, `assumingMemoryBound`,
`memcpy`/`memset`, seguido de rastreamento manual de cada call site até a origem do dado
(arquivo do usuário, pacote de rede, retorno de API do FFmpeg/CoreAudio/VideoToolbox) para
confirmar alcançabilidade. Os `fatalError("init(coder:) ...")` em `UIView`/`NSView`
subclasses foram descartados: nenhuma dessas classes é instanciada via Storyboard/XIB no
fork, então esse caminho não é alcançável.

---

## 1. Linha de estilo ASS malformada derruba o parser de legenda (índice fora dos limites)

**Arquivo:** `Sources/KSPlayer/Subtitle/KSParseProtocol.swift`
**Linhas:** 57–70 (bug em 67–68)
**Severidade:** crítica

```swift
guard var keys = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
    return false
}
...
while scanner.scanString("Style:") != nil {
    _ = scanner.scanString("Format: ")
    guard let values = scanner.scanUpToCharacters(from: .newlines)?.components(separatedBy: ",") else {
        continue
    }
    var dic = [String: String]()
    for i in 1 ..< keys.count {
        dic[keys[i]] = values[i]   // <- values[i] sem checar values.count
    }
    styleMap[values[0]] = dic.parseASSStyle()
}
```

`keys` vem da linha `Format:` da seção `[Script Info]` de um arquivo `.ass`; `values` vem de
cada linha `Style:` seguinte, dividida por vírgula. Nada garante que `values.count >=
keys.count` — são duas linhas de texto independentes do arquivo de legenda. Se qualquer
linha `Style:` tiver menos campos separados por vírgula do que a linha `Format:` declarou
(arquivo `.ass` truncado, gerado por conversor de terceiros, ou corrompido em download),
`values[i]` estoura o índice do array e o processo crasha com "Index out of range".

**Cenário concreto de falha:** usuário carrega um `.mkv`/`.ass` cuja legenda embutida tem
`Format: Name, Fontname, Fontsize, ..., MarginV, Encoding` (10+ campos) mas uma linha
`Style: Default,Arial,20` com só 3 campos (arquivo cortado/mal reencodado — comum em rips
de terceiros). O parser é chamado a cada troca de faixa de legenda; não há try/catch em
volta desse parsing, então o crash derruba o player inteiro, não só a legenda.

---

## 2. Recriação de `VTDecompressionSession` falha e crasha exatamente no caminho de recuperação de erro

**Arquivo:** `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift`
**Linha:** 33
**Severidade:** alta

```swift
func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
    if needReconfig {
        // 解决从后台切换到前台，解码失败的问题
        session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
        doFlushCodec()
        needReconfig = false
    }
```

`DecompressionSession.init?` é falível (retorna `nil` se `VTDecompressionSessionCreate`
falhar — ver linhas 139–141 do mesmo arquivo). O único lugar que seta `needReconfig = true`
é exatamente o handler de erro do VideoToolbox (`kVTInvalidSessionErr` /
`kVTVideoDecoderMalfunctionErr` / `kVTVideoDecoderBadDataErr`) quando o app volta do
background — o comentário do próprio autor confirma isso ("解决从后台切换到前台，解码失败的问题").
Ou seja: no exato cenário em que a criação da sessão de decodificação tem mais chance de
falhar de novo (recursos de hardware ainda contendidos logo após voltar do background), o
código força-desembrulha o resultado com `!`.

**Cenário concreto de falha:** usuário troca de app durante a reprodução em tvOS/iOS,
volta para o player; o decoder de vídeo em hardware relata `kVTInvalidSessionErr` em um
frame não-chave, o código tenta recriar a sessão e o VideoToolbox falha de novo (device
ainda liberando recursos de outra sessão, ou memória de vídeo pressionada) → `nil!` → crash
imediato, ao invés de cair para o fallback de software decoding que o resto do arquivo já
sabe fazer (`MEPlayerItemTrack.swift` troca para `FFmpegDecode` só quando o **catch** do
`decodeFrame` é acionado, mas aqui o crash acontece antes de chegar no catch).

---

## 3. Conversão de NAL 3-byte→4-byte lê além do buffer do pacote (sem checar limites)

**Arquivo:** `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift`
**Linhas:** 160–177
**Severidade:** alta

```swift
fileprivate func getSampleBuffer(isConvertNALSize: Bool, data: UnsafeMutablePointer<UInt8>, size: Int) throws -> CMSampleBuffer {
    if isConvertNALSize {
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        let status = avio_open_dyn_buf(&ioContext)
        if status == 0 {
            var nalSize: UInt32 = 0
            let end = data + size
            var nalStart = data
            while nalStart < end {
                nalSize = UInt32(nalStart[0]) << 16 | UInt32(nalStart[1]) << 8 | UInt32(nalStart[2])
                avio_wb32(ioContext, nalSize)
                nalStart += 3
                avio_write(ioContext, nalStart, Int32(nalSize))
                nalStart += Int(nalSize)
            }
```

Esse caminho é ativado quando `FFmpegAssetTrack.isConvertNALSize == true`
(`FFmpegAssetTrack.swift:188-190`, para H.264 cujo `extradata[4] == 0xFE` — quirk real e
conhecido de streams com length-size de 3 bytes), portanto é alcançável com conteúdo H.264
real, não é um modo exótico.

O laço só checa `nalStart < end` antes de ler **3 bytes** (`nalStart[0..2]`) — se sobrarem 1
ou 2 bytes antes de `end`, `nalStart[1]`/`nalStart[2]` já leem além do buffer alocado pelo
FFmpeg para o pacote. Pior: `nalSize` (24 bits, até 16 MB) não é validado contra o espaço
restante (`end - nalStart - 3`) antes de `avio_write(ioContext, nalStart, Int32(nalSize))`
— se o valor lido estiver corrompido/truncado, a função copia até `nalSize` bytes a partir
de `nalStart` para o buffer de demux, lendo memória de heap muito além do pacote de origem.

**Cenário concreto de falha:** pacote H.264 truncado/corrompido (stream de rede
interrompido, arquivo parcialmente baixado, ou remux malfeito) com um comprimento de NAL
inconsistente com o tamanho real do pacote → leitura fora dos limites do heap, que pode
crashar ao cruzar um guard page não mapeado ou vazar memória adjacente para dentro do
`CMSampleBuffer` entregue ao VideoToolbox.

---

## 4. `swr_convert` retornando erro (negativo) crasha em vez de propagar a falha

**Arquivo:** `Sources/KSPlayer/MEPlayer/Resample.swift`
**Linha:** 262
**Severidade:** alta

```swift
let frame = AudioFrame(dataSize: Int(bufferSize[0]), audioFormat: descriptor.audioFormat)
frame.numberOfSamples = UInt32(swr_convert(swrContext, &frame.data, outSamples, &frameBuffer, numberOfSamples))
```

A documentação do FFmpeg para `swr_convert` é explícita: "return number of samples output
per channel, negative value on error". Qualquer erro de resampling (canal/layout
inconsistente após uma reconfiguração no meio do stream, falha interna de alocação em
`libswresample`, frame de entrada malformado) faz `swr_convert` retornar um `Int32`
negativo. `UInt32(negativo)` em Swift crasha com "Fatal error: Negative value is not
representable in UInt32" — não há checagem do valor de retorno antes da conversão.

**Cenário concreto de falha:** troca de formato de áudio no meio do stream (ex.: track
com mudança de channel layout, comum em transmissões ao vivo/HLS com anúncios) força
`setup(descriptor:)` a reconfigurar o `SwrContext`; se essa primeira chamada a
`swr_convert` após a reconfiguração falhar internamente, o app crasha instantaneamente no
pipeline de áudio, no lugar de descartar o frame e continuar.

---

## 5. Divisão por `numberOfSamples == 0` no backend `AudioRendererPlayer`

**Arquivo:** `Sources/KSPlayer/MEPlayer/AudioRendererPlayer.swift`
**Linha:** 120
**Severidade:** média-alta

```swift
guard var render = renderSource?.getAudioOutputRender() else { break }
var array = [render]
let loopCount = Int32(render.audioFormat.sampleRate) / 20 / Int32(render.numberOfSamples) - 2
```

`render.numberOfSamples` é preenchido por `swr_convert` (ver finding 4) e pode
legitimamente ser **0** — não só em erro, mas no caso normal em que o resampler ainda está
bufferizando internamente e não tem amostras suficientes para produzir uma saída completa
(comportamento documentado do `libswresample`, comum logo após um seek/flush ou troca de
formato). `Int32(0)` como divisor crasha com "Fatal error: Divided by zero".

Os outros três backends de áudio (`AudioUnitPlayer`, `AudioGraphPlayer`,
`AudioEnginePlayer`) tratam esse mesmo caso corretamente via
`guard residueLinesize > 0 else { ...; continue }`; só o `AudioRendererPlayer` (usado para
`AVSampleBufferAudioRenderer`, relevante em tvOS para passthrough/áudio espacial via
`KSOptions.audioPlayerType = AudioRendererPlayer.self`) tem essa divisão direta sem guarda.

**Cenário concreto de falha:** app configura `AudioRendererPlayer` (cenário plausível para
o objetivo do fork de dar suporte a áudio espacial/Atmos em paridade com o Infuse); logo
após um seek ou troca de faixa de áudio, a primeira chamada a `request()` pega um frame com
`numberOfSamples == 0` → crash imediato.

---

## 6. Force unwrap de `mData` inconsistente com a checagem feita linhas antes (3 arquivos)

**Arquivos e linhas:**
- `Sources/KSPlayer/MEPlayer/AudioEnginePlayer.swift:308` (backend **padrão**,
  `KSOptions.audioPlayerType` default — `Model.swift:85`)
- `Sources/KSPlayer/MEPlayer/AudioUnitPlayer.swift:180`
- `Sources/KSPlayer/MEPlayer/AudioGraphPlayer.swift:286`

**Severidade:** média

```swift
for i in 0 ..< min(ioData.count, currentRender.data.count) {
    if let source = currentRender.data[i], let destination = ioData[i].mData {   // <- checa mData
        (destination + ioDataWriteOffset).copyMemory(from: source + offset, byteCount: bytesToCopy)
    }
}
...
for i in 0 ..< ioData.count {
    let sizeLeft = Int(ioData[i].mDataByteSize - sizeCopied)
    if sizeLeft > 0 {
        memset(ioData[i].mData! + Int(sizeCopied), 0, sizeLeft)   // <- força mData! sem checar
    }
}
```

Dentro da mesma função (`audioPlayerShouldInputData`), o laço de cópia trata
`ioData[i].mData` como potencialmente `nil` (via `if let`), mas o laço de preenchimento de
silêncio logo abaixo força-desembrulha o mesmo campo (`ioData[i].mData!`) sem qualquer
checagem. Se algum buffer do `AudioBufferList`/`AVAudioSourceNode` vier com `mData == nil`
— situação que o próprio código reconhece como possível no primeiro laço — a segunda
metade da função crasha.

**Cenário concreto de falha:** callback de render de áudio (thread de tempo real do
CoreAudio/AVAudioEngine) recebe um `AudioBufferList` com um buffer de canal sem `mData`
alocado (buffer "nulo" — cenário documentado em configurações de I/O Audio Unit com
`kAudioUnitProperty_ShouldAllocateBuffer` desligado, ou canais extras não usados em layouts
multicanal); o primeiro laço ignora esse canal silenciosamente, mas o segundo laço
(executado sempre, incondicionalmente, para todo `i` em `0..<ioData.count`) crasha ao
tentar zerar esse mesmo buffer.

---

## 7. `MTLCreateSystemDefaultDevice()!` e biblioteca de shaders sem fallback

**Arquivo:** `Sources/KSPlayer/Metal/MetalRender.swift`
**Linhas:** 15–23
**Severidade:** média

```swift
static let device = MTLCreateSystemDefaultDevice()!
static let library: MTLLibrary = {
    var library: MTLLibrary!
    library = device.makeDefaultLibrary()
    if library == nil {
        library = try? device.makeDefaultLibrary(bundle: .module)
    }
    return library   // <- IUO implicitamente forçado no retorno se ambas tentativas falharem
}()
```

`MTLCreateSystemDefaultDevice()` pode retornar `nil` quando Metal não está disponível (Mac
rodando em VM sem passthrough de GPU, ou builds de CI/macOS sem aceleração 3D — o pacote
declara suporte a `.macOS(.v10_15)` em `Package.swift`). Se isso acontecer, o `!` na
declaração `static let device` crasha na primeira referência a `MetalRender` (ou seja,
antes mesmo de qualquer vídeo tocar, já que `MetalPlayView`/`DisplayModel` acessam
`MetalRender.device` no `init`). Da mesma forma, se `device.makeDefaultLibrary()` **e** o
fallback para o bundle do pacote falharem (por exemplo, se o fork for integrado de outra
forma que não via SwiftPM e o recurso `Metal/Shaders.metal` compilado não for empacotado
corretamente — ver `resources: [.process("Metal/Shaders.metal")]` em `Package.swift`), a
variável local `library` (declarada `MTLLibrary!`) permanece `nil` e o `return library`
implícito crasha ao converter o IUO nil para o tipo de retorno não-opcional `MTLLibrary`.

**Cenário concreto de falha:** relevante principalmente para o alvo macOS do pacote
(headless/CI/VM sem GPU) e para qualquer reempacotamento do fork que não preserve o
`resources:` do `Package.swift` original — cenário real ao "evoluir o fork" para embutir em
outro projeto/target.

---

## 8. `CVDisplayLinkCreateWithActiveCGDisplays` sem checar o status antes do force unwrap (shim macOS de `CADisplayLink`)

**Arquivo:** `Sources/KSPlayer/MEPlayer/MetalPlayView.swift`
**Linhas:** 410–420 (também 422–431, segundo `init`)
**Severidade:** baixa

```swift
public init(target: NSObject, selector: Selector) {
    var displayLink: CVDisplayLink?
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    self.displayLink = displayLink!
    ...
}
```

`CVDisplayLinkCreateWithActiveCGDisplays` retorna um `CVReturn` que não é checado; a API
pode falhar (por exemplo, sem displays ativos — sessão remota/headless no macOS) deixando
`displayLink` como `nil`, e o `!` seguinte crasha. Esse shim só é compilado
`#if os(macOS)`, então só afeta o alvo macOS do pacote.

---

## 9. Force cast dependente de string de módulo hardcoded

**Arquivo:** `Sources/KSPlayer/AVPlayer/KSPlayerLayer.swift`
**Linhas:** 137, 203
**Severidade:** baixa

```swift
firstPlayerType = NSClassFromString("KSPlayer.KSMEPlayer") as! MediaPlayerProtocol.Type
```

Funciona hoje porque o pacote se chama `KSPlayer` (`Package.swift:6`) e `KSMEPlayer` é uma
`NSObject` sem `@objc(nome)` customizado, então o nome Objective-C runtime bate com a
string hardcoded. Esse caminho só é exercitado quando `options.display != .plane` (modos
VR/VRBox, selecionáveis via `KSOptions`/UI). Se o fork for renomeado como módulo (comum ao
embutir/vendorizar um pacote local dentro de outro projeto, que é exatamente o plano de
evolução citado para o StreamHub), `NSClassFromString` passa a retornar `nil` e o `as!`
crasha sempre que o modo VR for selecionado — sem nenhum sinal em tempo de compilação.

---

## Notas menores (não listadas como findings numerados por menor confiança de alcançabilidade)

- `Sources/KSPlayer/MEPlayer/Model.swift:369-371`: a checagem `if dataByteSize > dataSize
  { assertionFailure(...) }` em `AudioFrame.toCMSampleBuffer()` só trava em build Debug;
  em Release o código segue e `CMBlockBufferReplaceDataBytes` (linha 386-391) copia
  `dataByteSize` bytes a partir de `data[i]!`, que factualmente só tem `dataSize` bytes
  alocados — se a invariante (mantida hoje pelo contrato do `swr_convert`) for violada por
  qualquer motivo, isso é uma leitura fora dos limites silenciosa em produção.
- `Sources/KSPlayer/Metal/PixelBufferProtocol.swift:227,260`: `bytes[i]!` e `buffers[0]!`
  força-desembrulham, respectivamente, um ponteiro de plano do `AVFrame` decodificado por
  software e um `MTLBuffer` cuja alocação (`device.makeBuffer`) pode retornar `nil` sob
  pressão de memória. Caminho de menor frequência (apenas decode por software /
  `cgImage()`/thumbnail), mas sem tratamento de falha.
