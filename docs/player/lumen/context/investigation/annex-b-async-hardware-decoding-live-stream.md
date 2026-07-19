# Annex-B async hardware decoding (live stream)

## Status

Parcial. (Investigação original concluiu "presente"; corrigido após verificação adversarial — ver seção `## Verificação`.)

## Evidência

- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:13-109` — `VideoToolboxDecode: DecodeProtocol` decodifica via `VTDecompressionSessionDecodeFrame` com flag `._EnableAsynchronousDecompression` e callback de conclusão: o caminho de decode assíncrono por hardware existe e é real.
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:160-184` — `getSampleBuffer(isConvertNALSize:data:size:)`: única conversão de NAL do codebase. Lê prefixo de tamanho de **3 bytes** (`UInt32(nalStart[0]) << 16 | UInt32(nalStart[1]) << 8 | UInt32(nalStart[2])`) e regrava como 4 bytes (`avio_wb32`).
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:186-193` — detecção: `extradataSize >= 5 && extradata[4] == 0xFE` → patch para `0xFF` e `isConvertNALSize = true`.
- `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift:300-315` — `makeDecode`: `VideoToolboxDecode` só é usado com `options.asynchronousDecompression && options.hardwareDecode` **e** se `DecompressionSession(assetTrack:options:)` não retornar `nil`; senão, fallback silencioso para `FFmpegDecode`.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:477-479` — defaults: `hardwareDecode = true`, `asynchronousDecompression = false`, com comentário de que o hardware decode "auto-desenvolvido" fica desligado porque alguns vídeos têm pts incorreto no `AVPacket`.
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:20-54` e `:90-91` — caminho padrão de hardware: hwaccel interno do FFmpeg (`get_format` + `av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_VIDEOTOOLBOX)`), gated por `options.hardwareDecode`.

## Como funciona (o que existe de fato)

O fork GPL tem um caminho de decode assíncrono por VideoToolbox (`VideoToolboxDecode`), desligado por padrão (`KSOptions.asynchronousDecompression = false`). Esse caminho funciona para streams **em formato de container** (avcC/hvcC — MP4, MKV), incluindo o caso raro de avcC com NAL length de 3 bytes, que é convertido por pacote para 4 bytes em `getSampleBuffer`. Para streams ao vivo Annex-B (MPEG-TS, RTSP), o hardware decode acontece apenas pelo hwaccel interno do FFmpeg (caminho `FFmpegDecode` + `get_format`), que é o pipeline padrão dirigido pelo libavcodec — não o caminho VT assíncrono próprio.

## O que falta

Tudo que caracteriza "Annex-B async hardware decoding (live stream)" na versão paga:

1. Conversor de bitstream Annex-B real: parsing de start codes (`00 00 01` / `00 00 00 01`) → length-prefixed. O conversor existente assume prefixos de tamanho de 3 bytes; dados Annex-B seriam mal interpretados (os 3 primeiros bytes de um start code de 4 bytes viram `nalSize = 0`).
2. Extração de SPS/PPS/VPS in-band para construir a `CMVideoFormatDescription` quando `extradata` é nulo (caso típico de TS/RTSP com parameter sets no próprio bitstream).
3. Reconstrução da format description / da sessão VT em mudança de parâmetros no meio do stream (comum em live). `VTDecompressionSessionCanAcceptFormatDescription` está literalmente comentado (`VideoToolboxDecode.swift:127`).
4. Qualquer uso de bitstream filter do FFmpeg (`av_bsf_*`): inexistente no codebase — a única referência é a constante de erro `bitstreamFilterNotFound` (`AVFFmpegExtension.swift:500`).

## Verificação

**Veredito: REFUTADO em parte — status rebaixado de "presente" para "parcial". A tabela oficial (feature exclusiva da versão paga) está essencialmente correta quanto ao Annex-B.**

As linhas citadas pela investigação original existem e foram conferidas uma a uma, mas a interpretação do ponto central está errada:

1. **A conversão em `getSampleBuffer` não é Annex-B → length-prefixed.** O loop (`VideoToolboxDecode.swift:168-173`) lê um prefixo de tamanho big-endian de **3 bytes** e o regrava como 4 bytes. Isso é a conversão avcC `nal_length_size == 3` → `nal_length_size == 4` (pacotes já length-prefixed, vindos de MP4/MKV). Annex-B usa start codes, não prefixos de tamanho; se um pacote Annex-B entrasse nesse loop, `00 00 00` seria lido como `nalSize = 0` e o buffer resultante seria lixo.

2. **A detecção `extradata[4] == 0xFE` não identifica "stream Annex-B-like".** No avcC, o byte 4 é `0b111111xx` onde `xx = lengthSizeMinusOne`: `0xFF` = NAL length 4 bytes, `0xFE` = 3 bytes. O patch `0xFE → 0xFF` (`FFmpegAssetTrack.swift:188-190`) apenas normaliza um avcC de 3 bytes para 4. Extradata de fonte live real é Annex-B começando com start code (byte 4 = header do NAL, ex. `0x67` para SPS) ou é nula (parameter sets in-band) — em ambos os casos `isConvertNALSize = false`. (Para HEVC/hvcC o byte 4 nem é o campo de length size, então a checagem é específica de H.264.)

3. **Um stream live Annex-B nunca chega a usar o caminho VT assíncrono.** Sem extradata, `atomsData = nil` e a `CMFormatDescription` sai sem atom avcC/hvcC; com extradata Annex-B, o atom contém dados inválidos para o VT. Nos dois casos a `VTDecompressionSessionCreate` falha (sem parameter sets, com `RequireHardwareAcceleratedVideoDecoder`), `DecompressionSession.init` retorna `nil` e `makeDecode` (`MEPlayerItemTrack.swift:306-309`) cai silenciosamente para `FFmpegDecode` — mesmo com `asynchronousDecompression = true`.

4. **Buscas adversariais não acharam implementação alternativa.** `rg -i "annex|bsf|mp4toannexb|startcode|extract_extradata"` em `Sources/` e `Demo/` só retorna a constante de erro; `DecompressionSession`/`VTDecompressionSession` só existem em `VideoToolboxDecode.swift` e `MEPlayerItemTrack.swift`; não há código condicional por plataforma nem implementação em `Demo/`. O hwaccel do FFmpeg (que de fato decodifica Annex-B em hardware, pois o libavcodec parseia SPS/PPS do bitstream) é o caminho síncrono padrão (`FFmpegDecode`), não a feature "async por VT próprio" da tabela.

**Resumo:** o que existe é decodificação assíncrona por hardware para streams avcC/hvcC de container (atrás de flag desligado por padrão) — infraestrutura async presente, suporte a Annex-B/live ausente. Por isso "parcial", e não "presente".

Observação lateral: `context/investigation/hardware-accelerator-videotoolbox.md:9,19` repete a mesma descrição incorreta ("conversão Annex-B → length-prefixed") — vale corrigir naquele arquivo também.
