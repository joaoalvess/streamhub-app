# Auditoria de interop com FFmpeg — KSPlayer (fork StreamHub)

Escopo: `Sources/KSPlayer/MEPlayer/` (camada que fala diretamente com a API C do
FFmpeg/FFmpegKit 6.1.4). Foco específico desta auditoria: códigos de erro de função
`av_*`/`avcodec_*`/`avformat_*`/`swr_*`/`avio_*` ignorados ou mal propagados, alocações
`av_*`/`avio_*` sem `av_free`/`av_buffer_unref` correspondente, suposições sobre
formatos de pixel/amostra e layouts de canal, conversões de timestamp/timebase, e uso de
campos/funções deprecadas da API do FFmpeg 6.

Cada achado abaixo foi confirmado lendo o código-fonte (arquivo/linha citados) e
verificado contra o contrato documentado da função FFmpeg envolvida (comentários do
próprio header, quando citados de memória, ou o comportamento já documentado em
comentários do próprio fork).

## Nota de escopo — achados já cobertos em outros documentos

Esta auditoria roda em paralelo a outras (`memoria.md`, `performance.md`,
`crash-safety.md`, `playback-core.md`, etc.). Ao investigar interop com FFmpeg eu
cheguei de forma independente a quatro problemas que **já estão documentados em
detalhe** nesses outros arquivos — não os repito aqui para evitar duplicação, só
referencio:

- `avcodec_send_packet` retornando `EAGAIN` descarta o pacote sem drenar
  `avcodec_receive_frame` nem reenviar — **`playback-core.md`, achado 3**
  (`FFmpegDecode.swift:38`).
- Seek trunca a parte fracionária do delta para `Int64` **antes** de multiplicar por
  `AV_TIME_BASE` — **`playback-core.md`, achado 1** (`MEPlayerItem.swift:456,478-479`).
- `MEFilter.filter()` vaza um `AVBufferRef` de `hw_frames_ctx` a cada frame (via
  `av_buffer_ref` sem `av_buffer_unref` correspondente) — **`performance.md`, achado 2**
  (`Filter.swift:126-133`).
- `swr_convert` retornando erro (negativo) é convertido direto para `UInt32` e crasha —
  **`crash-safety.md`, achado 4** (`Resample.swift:262`); o mesmo documento também cobre,
  no achado 3, a leitura fora dos limites no loop de conversão de NAL 3→4 bytes em
  `VideoToolboxDecode.swift:160-177`, e no achado 2 o vazamento do buffer `av_malloc`
  de `avio_close_dyn_buf` em `VideoToolboxDecode.getSampleBuffer` (também relatado em
  `memoria.md`, achado 2). `memoria.md` (achado 3) também já cobre o `AVPacket` de
  `ThumbnailController.getPeeks` reaproveitado sem `av_packet_unref` entre leituras.

Os achados abaixo são os que sobraram depois de eliminar essa sobreposição — todos
localizados em pontos de interop com o FFmpeg ainda não relatados nos outros documentos.

Também verifiquei explicitamente por deprecações comuns da API do FFmpeg 6
(`channels`/`channel_layout` no lugar de `AVChannelLayout`/`ch_layout`, `av_init_packet`,
`avcodec_decode_video2`/`avcodec_decode_audio4`, `av_register_all`): nenhuma ocorre em
`Sources/` — o fork já usa `ch_layout` e a API `avcodec_send_packet`/`avcodec_receive_frame`
de forma consistente. Não há achado de "campo deprecado" a reportar.

---

## 1. [ALTA] Hack de NAL-size (`extradata[4]` 0xFE→0xFF) corrompe o fallback de decodificação por software

**Arquivo:** `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift`
**Linhas:** 183–194, especialmente 189

```swift
var extradataSize = Int32(0)
var extradata = codecpar.extradata
let atomsData: Data?
if let extradata {
    extradataSize = codecpar.extradata_size
    if extradataSize >= 5, extradata[4] == 0xFE {
        extradata[4] = 0xFF                    // linha 189 — escreve através do ponteiro
        isConvertNALSize = true
    } else {
        isConvertNALSize = false
    }
    atomsData = Data(bytes: extradata, count: Int(extradataSize))
}
```

`codecpar` é um `struct AVCodecParameters` (valor), mas o campo `extradata` dentro dele é
um ponteiro (`UnsafeMutablePointer<UInt8>?`) — copiar a struct por valor **não copia o
buffer apontado**. Como `FFmpegAssetTrack.init(stream:)` constrói esse `codecpar` a
partir de `stream.pointee.codecpar.pointee` (`FFmpegAssetTrack.swift:72`), `extradata[4] =
0xFF` escreve **no buffer real do `AVStream`**, o mesmo que o FFmpeg usa internamente
para essa track pelo resto da sessão.

O byte 4 do extradata AVCC (`length_size_minus_one`, nos 2 bits baixos) é o campo que diz
ao parser H.264/HEVC quantos bytes cada prefixo de tamanho de NAL ocupa no bitstream.
`0xFE` = tamanho 3 (não-padrão, mas real em certos remuxes); o código só usa esse valor
para decidir se deve **reescrever o bitstream do pacote** de 3 para 4 bytes de tamanho de
NAL — só que essa reescrita só acontece no caminho `VideoToolboxDecode.getSampleBuffer`
(`VideoToolboxDecode.swift:160-177`, usado exclusivamente pela sessão `VTDecompressionSession`).

O problema: `extradata[4] = 0xFF` na linha 189 muda permanentemente o que o `codecpar`
**declara** (agora diz "tamanho de NAL = 4"), e essa é a mesma struct usada por
`FFmpegAssetTrack.createContext(options:)` → `AVCodecParameters.createContext`
(`AVFFmpegExtension.swift:80-120`) → `avcodec_parameters_to_context`, que faz uma cópia
profunda do extradata (com `length_size_minus_one` já mutado para 4) para o
`AVCodecContext` usado pelo decodificador comum (`FFmpegDecode`, `SyncPlayerItemTrack.makeDecode`,
`MEPlayerItemTrack.swift:301-315`). **Esse caminho não passa pelo `getSampleBuffer` que
reescreve o bitstream** — `FFmpegDecode.decodeFrame` (`FFmpegDecode.swift:38`) entrega o
pacote cru, direto de `av_read_frame`, ainda com prefixos de NAL de **3 bytes** de
verdade, para um `AVCodecContext` cujo extradata agora afirma que são **4 bytes**.

**Cenário concreto de falha:** um arquivo H.264/HEVC com esse quirk de extradata
(`extradata[4] == 0xFE`) é reproduzido em qualquer condição que caia no
`FFmpegDecode` em vez do `VideoToolboxDecode` explícito — `options.hardwareDecode ==
false` (padrão de fábrica em algumas configs, ou desligado automaticamente pelo
auto-rotate em `MEPlayerItem.swift:364`), `options.asynchronousDecompression == false`,
ou simplesmente a criação da `DecompressionSession` falhando (comum ao voltar de
background, ver `crash-safety.md` achado 2). O parser H.264/HEVC do FFmpeg passa a
interpretar cada prefixo de tamanho de NAL como 4 bytes quando o arquivo real tem 3,
deslocando a leitura de todos os NALs subsequentes do pacote — decodificação
corrompida/glitches severos ou falha total de decode (`avcodec_send_packet`/
`avcodec_receive_frame` reportando erro de bitstream), sem qualquer log que aponte para
a causa raiz (a mutação do extradata compartilhado).

**Correção sugerida:** aplicar a correção de `length_size_minus_one` numa **cópia** do
extradata usada só para a via VideoToolbox/CMFormatDescription (que já é o que
`atomsData` faz, no fundo — bastaria montar `atomsData` a partir de um buffer separado
em vez de mutar `extradata` in-place), preservando o extradata original (0xFE) na
`AVCodecParameters` que alimenta `avcodec_parameters_to_context` para o fallback via
software.

---

## 2. [MÉDIA] Buffer de extradata VP9 criado via `avio_close_dyn_buf` nunca é liberado com `av_free`

**Arquivo:** `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift`
**Linhas:** 196–211

```swift
if codecType.rawValue == kCMVideoCodecType_VP9 {
    // ff_videotoolbox_vpcc_extradata_create
    var ioContext: UnsafeMutablePointer<AVIOContext>?
    guard avio_open_dyn_buf(&ioContext) == 0 else {
        return nil
    }
    ff_isom_write_vpcc(nil, ioContext, nil, 0, &self.codecpar)
    extradataSize = avio_close_dyn_buf(ioContext, &extradata)   // linha 203
    guard let extradata else {
        return nil
    }
    var data = Data()
    var array: [UInt8] = [1, 0, 0, 0]
    data.append(&array, count: 4)
    data.append(extradata, count: Int(extradataSize))           // cópia para Data
    atomsData = data
    // `extradata` nunca é liberado
}
```

`avio_close_dyn_buf` devolve um buffer alocado internamente por `av_malloc`, cuja
liberação é responsabilidade documentada do chamador (mesmo contrato já identificado em
`memoria.md` achado 2 para o caso do `VideoToolboxDecode`). Aqui os bytes são copiados
para um `Data` Swift (`data.append(extradata, count:)`), mas o ponteiro `extradata`
original nunca recebe `av_free(extradata)` — o buffer nativo fica vazado.

Esse branch só roda uma vez por `FFmpegAssetTrack` de vídeo **sem extradata** cujo
`codecType` seja VP9 (streams VP9 crus, tipicamente vindos de contêineres que não
carregam a caixa `vpcC`/`VPCodecConfigurationBox`, como alguns remuxes de WebM→MP4 ou
streams ao vivo). Diferente do achado #1 de `memoria.md` (que vaza por *frame*), este
vaza uma vez por *track* — impacto bem menor, mas mesmo padrão de bug e no mesmo
arquivo.

**Cenário concreto de falha:** abrir um vídeo VP9 sem `vpcC` no extradata (raro, mas real
em pipelines de remux/transcodificação que descartam essa caixa) — cada abertura desse
tipo de arquivo vaza um pequeno buffer nativo (o tamanho da caixa `vpcC` sintetizada,
tipicamente poucas dezenas de bytes) que só é recuperado quando o processo termina. Em
uma sessão do StreamHub que abre múltiplos títulos VP9 desse tipo, o vazamento é
proporcional ao número de trocas de título, não ao tempo de reprodução.

**Correção sugerida:** chamar `av_free(extradata)` depois de `data.append(extradata,
count:)`.

---

## 3. [MÉDIA] `duration` do item trunca para segundos inteiros por divisão `Int64` prematura

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linha:** 243

```swift
duration = TimeInterval(max(formatCtx.pointee.duration, 0) / Int64(AV_TIME_BASE))
```

`formatCtx.pointee.duration` está em unidades de `AV_TIME_BASE` (microssegundos,
1_000_000 por segundo). A divisão `Int64 / Int64(AV_TIME_BASE)` é aritmética inteira —
qualquer parte fracionária de segundo é descartada **antes** da conversão para
`TimeInterval` (`Double`). Ou seja, `duration` nunca tem casas decimais: um arquivo com
duração real de 125.87s é reportado como exatamente `125.0`.

Isso é inconsistente com o padrão usado no resto do arquivo para converter
timestamps FFmpeg em segundos — `Timebase.cmtime(for:)` (`Model.swift:183`) monta um
`CMTime` e só divide para `Double` no `.seconds` final, preservando a fração. Bastava
fazer o mesmo aqui: `TimeInterval(max(formatCtx.pointee.duration, 0)) /
TimeInterval(AV_TIME_BASE)` (dividir como `Double`, não como `Int64`).

**Cenário concreto de falha:** qualquer vídeo VOD cuja duração real não seja um número
inteiro de segundos (a esmagadora maioria) — a UI de progresso/duração do player
(barra de scrubbing, contador "restam Xm Ys" no StreamHub) sempre reporta até ~1s a
menos que a duração real, e cálculos que dependem de `duration` (ex.:
`fileSize = Double(formatCtx.pointee.bit_rate) * duration / 8` na linha seguinte, ou o
`fmod(seekCommand.itemTime.seconds, duration)` do `AVPlaybackCoordinator` documentado em
`playback-core.md` achado 5) herdam esse erro sistemático.

**Correção sugerida:** `duration = TimeInterval(max(formatCtx.pointee.duration, 0)) /
TimeInterval(AV_TIME_BASE)`.

---

## 4. [MÉDIA] `startRecord()` ignora o retorno de `avio_open` — gravação pode falhar silenciosamente

**Arquivo:** `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift`
**Linhas:** 318–326

```swift
avio_open(&(outputFormatCtx.pointee.pb), filename, AVIO_FLAG_WRITE)
ret = avformat_write_header(outputFormatCtx, nil)
guard ret >= 0 else {
    KSLog(NSError(errorCode: .formatWriteHeader, avErrorCode: ret))
    avformat_close_input(&self.outputFormatCtx)
    return
}
outputPacket = av_packet_alloc()
```

O valor de retorno de `avio_open` é descartado (nem atribuído a uma variável). Se
`avio_open` falhar — caminho inválido/sem permissão de escrita, disco cheio, protocolo
não suportado pelo muxer de destino — `outputFormatCtx.pointee.pb` permanece `nil`. As
chamadas `avio_*` internas do FFmpeg em cima de um `AVIOContext` nulo tipicamente não
crasham (retornam sem operar), então `avformat_write_header` pode continuar e retornar
sucesso (`ret >= 0`) mesmo sem nenhum I/O real acontecendo — a gravação segue rodando
"normalmente" (via `av_interleaved_write_frame` em `MEPlayerItem.reading()`, linha 542)
sem nunca escrever um único byte em disco, e sem que `KSLog`/algum erro seja emitido em
lugar nenhum.

**Cenário concreto de falha:** o app chama `options.outputURL` para gravar a sessão
(feature exposta em `startRecord(url:)`, chamada de `openThread()` linha 260-262) para um
caminho sem permissão de escrita ou um volume que ficou indisponível. A função retorna
normalmente, parece ter iniciado a gravação, e ao final da reprodução o app encontra um
arquivo ausente ou vazio, sem nenhum erro reportado para diagnosticar a causa.

**Correção sugerida:** capturar o retorno de `avio_open` e tratar falha do mesmo jeito
que as outras chamadas desta função (`KSLog` + early return antes de
`avformat_write_header`).

---

## 5. [BAIXA] `NSError` de "decoder não encontrado" carrega um `avErrorCode` obsoleto (sempre 0/"Success")

**Arquivo:** `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift`
**Linhas:** 85–96

```swift
var result = avcodec_parameters_to_context(codecContext, &self)
guard result == 0 else {
    avcodec_free_context(&codecContextOption)
    throw NSError(errorCode: .codecContextSetParam, avErrorCode: result)
}
if codec_type == AVMEDIA_TYPE_VIDEO, options?.hardwareDecode ?? false {
    codecContext.getFormat()
}
guard let codec = avcodec_find_decoder(codecContext.pointee.codec_id) else {
    avcodec_free_context(&codecContextOption)
    throw NSError(errorCode: .codecContextFindDecoder, avErrorCode: result)   // linha 95
}
```

No `throw` da linha 95, `result` é o mesmo valor já validado como `== 0` no `guard` da
linha 86 (não foi reatribuído entre as duas linhas) — ou seja, todo `NSError` de "decoder
não encontrado" carrega `avErrorCode: 0`. `String(avErrorCode:)` (`AVFFmpegExtension.swift:470-476`)
chama `av_make_error_string(buf, size, 0)`, que devolve a string genérica de sucesso (não
uma mensagem FFmpeg reconhecida, já que `0` não é um código `AVERROR` válido) — na
prática, o `NSError.userInfo[NSUnderlyingErrorKey]` desse erro específico sempre mostra
algo como "Success" em vez de qualquer indício de que o decoder é que faltou.

**Cenário concreto de falha:** o app tenta reproduzir um arquivo com um codec para o qual
o FFmpegKit não tem decoder habilitado/compilado (ex.: um codec proprietário raro, ou uma
build do FFmpegKit sem um decoder específico) — o erro reportado ao usuário/logs
(`KSLog`/tela de erro do KSMEPlayer) mostra "Success" como causa subjacente, escondendo o
diagnóstico real ("decoder not found") de quem for investigar o log depois.

**Correção sugerida:** usar `AVError.decoderNotFound.code` (já definido em
`AVFFmpegExtension.swift:506`) no lugar de `result` nesse `throw` específico.

---

## 6. [BAIXA] `get_format` pode vazar o `AVHWDeviceContext` anterior se renegociado mais de uma vez

**Arquivo:** `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift`
**Linhas:** 20–54, especialmente 28–33

```swift
extension UnsafeMutablePointer where Pointee == AVCodecContext {
    func getFormat() {
        pointee.get_format = { ctx, fmt -> AVPixelFormat in
            ...
            while fmt[i] != AV_PIX_FMT_NONE {
                if fmt[i] == AV_PIX_FMT_VIDEOTOOLBOX {
                    let deviceCtx = av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_VIDEOTOOLBOX)
                    if deviceCtx == nil {
                        break
                    }
                    // 只要有hw_device_ctx就可以了。不需要hw_frames_ctx
                    ctx.pointee.hw_device_ctx = deviceCtx    // sobrescreve sem av_buffer_unref
                    return fmt[i]
                }
                i += 1
            }
            return fmt[0]
        }
    }
}
```

`get_format` é o callback que o libavcodec chama para negociar o formato de pixel de
saída — normalmente uma vez por abertura de decoder, mas pode ser chamado de novo se o
stream renegociar formato/resolução no meio da decodificação (mudança de parâmetros
mid-stream, comum em transmissões ao vivo/HLS com troca de qualidade). Cada invocação que
cai no ramo `AV_PIX_FMT_VIDEOTOOLBOX` cria um **novo** `AVHWDeviceContext` via
`av_hwdevice_ctx_alloc` e o atribui direto a `ctx.pointee.hw_device_ctx`, sem antes
liberar (`av_buffer_unref`) o que já estivesse lá de uma chamada anterior. Se `get_format`
rodar mais de uma vez para o mesmo `AVCodecContext`, o `AVHWDeviceContext` da vez anterior
perde a única referência que o Swift/FFmpeg tinha para liberá-lo.

**Cenário concreto de falha:** decodificação por hardware habilitada (`options.hardwareDecode
== true`) sem a `DecompressionSession` explícita (caminho `FFmpegDecode` — mesmo cenário
de `performance.md` achado 2) em conteúdo que força uma renegociação de formato de vídeo
no meio da reprodução (troca de qualidade em HLS ao vivo, ou um stream com mudança de
`pix_fmt` reportada pelo demuxer). Cada renegociação vaza um `AVHWDeviceContext` inteiro
(bem mais pesado que o `AVBufferRef` de `hw_frames_ctx` do achado de `performance.md`,
já que aqui é o dispositivo, não só um frame). Impacto menor em VOD comum (só uma
negociação por sessão), mas real em cenários de live/adaptativo.

**Correção sugerida:** antes de atribuir o novo `deviceCtx`, liberar o anterior:
`if ctx.pointee.hw_device_ctx != nil { av_buffer_unref(&ctx.pointee.hw_device_ctx) }`.

---

## 7. [BAIXA] `best_effort_timestamp` não é checado contra `AV_NOPTS_VALUE` antes de virar timestamp de thumbnail

**Arquivo:** `Sources/KSPlayer/MEPlayer/ThumbnailController.swift`
**Linhas:** 118–122

```swift
let currentTimeStamp = frame.pointee.best_effort_timestamp
if let image {
    let thumbnail = FFThumbnail(image: image, time: timeBase.cmtime(for: currentTimeStamp).seconds)
    ...
}
```

`best_effort_timestamp` pode ser `AV_NOPTS_VALUE` (`Int64.min`) quando o FFmpeg não
consegue estimar nenhum PTS/DTS confiável para o frame — situação mais provável logo
após um `av_seek_frame` para uma posição arbitrária calculada (`seek_pos = interval *
Int64(i) + videoStream.pointee.start_time`, linha 95), que é exatamente o padrão de uso
deste método (100 seeks às cegas ao longo do arquivo para gerar a trilha de thumbnails).
Sem essa checagem, `timeBase.cmtime(for: Int64.min)` (`Model.swift:183`) produz um
`CMTime`/`.seconds` com um valor absurdamente grande e negativo, que vira o campo `time`
do `FFThumbnail` entregue ao delegate.

**Cenário concreto de falha:** gerar thumbnails de scrubbing para um arquivo cujo primeiro
segmento pós-seek não tem PTS/DTS resolvível (comum logo no início do arquivo, ou em
streams com PTS ausente reconstruído via `AVFMT_FLAG_GENPTS` de forma incompleta) — a
lista de thumbnails entregue via `didUpdate(thumbnails:forFile:withProgress:)` contém uma
entrada com `time` absurdo (um número enorme negativo em vez de um instante real do
vídeo), que pode quebrar a ordenação/posicionamento da UI de preview de scrubbing no
StreamHub se ela assumir que `time` está sempre dentro de `[0, duration]`.

**Correção sugerida:** descartar o frame (`continue`/não anexar) quando
`currentTimeStamp == Int64.min`, em vez de propagá-lo para `FFThumbnail`.

---

## Resumo

| # | Severidade | Arquivo | Problema |
|---|---|---|---|
| 1 | Alta | `FFmpegAssetTrack.swift:189` | Mutação de `extradata[4]` (hack de NAL-size p/ VideoToolbox) corrompe o fallback de decode por software |
| 2 | Média | `FFmpegAssetTrack.swift:203-210` | Buffer de `avio_close_dyn_buf` (extradata VP9 sintetizado) nunca liberado com `av_free` |
| 3 | Média | `MEPlayerItem.swift:243` | `duration` truncada para segundos inteiros por divisão `Int64` antes da conversão para `Double` |
| 4 | Média | `MEPlayerItem.swift:318` | Retorno de `avio_open` ignorado em `startRecord()` — gravação pode falhar silenciosamente |
| 5 | Baixa | `AVFFmpegExtension.swift:95` | `NSError` de decoder-não-encontrado carrega `avErrorCode` obsoleto (sempre 0/"Success") |
| 6 | Baixa | `AVFFmpegExtension.swift:28-33` | `get_format` pode vazar `AVHWDeviceContext` anterior se renegociado mais de uma vez |
| 7 | Baixa | `ThumbnailController.swift:118-120` | `best_effort_timestamp == AV_NOPTS_VALUE` não é checado antes de gerar o timestamp da thumbnail |

Ver também a seção "Nota de escopo" no topo deste documento para os achados de interop
com FFmpeg já cobertos em `memoria.md`, `performance.md`, `crash-safety.md` e
`playback-core.md` (EAGAIN de `avcodec_send_packet`, truncamento do seek, leak de
`hw_frames_ctx` em `MEFilter`, crash de `swr_convert`, leitura fora dos limites na
conversão de NAL, leak do buffer de `VideoToolboxDecode`, e reuso de `AVPacket` sem
unref em `ThumbnailController`).
