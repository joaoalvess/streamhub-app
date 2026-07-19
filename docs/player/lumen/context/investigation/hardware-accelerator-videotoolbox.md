## Status

Presente.

## Evidência

- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:13-109` — classe `VideoToolboxDecode: DecodeProtocol` que decodifica pacotes via `VTDecompressionSessionDecodeFrame`, com callback assíncrono, tratamento de erro (`kVTInvalidSessionErr`, `kVTVideoDecoderMalfunctionErr`, `kVTVideoDecoderBadDataErr`) e reconfiguração automática de sessão ao voltar do background (`needReconfig`).
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:111-156` — `DecompressionSession` cria a `VTDecompressionSession` real (`VTDecompressionSessionCreate`), configurando `pixelFormatType`, compatibilidade Metal (`kCVPixelBufferMetalCompatibilityKey`), HDR (`kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata`) e transferência de cor de destino (`kVTPixelTransferPropertyKey_Destination*`).
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:159-200` — extensão de `CMFormatDescription` que monta o `CMSampleBuffer` a partir do pacote FFmpeg, incluindo conversão de NAL size (Annex-B → length-prefixed) quando necessário (`isConvertNALSize`).
- `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift:300-315` — `makeDecode(assetTrack:)`: quando `mediaType == .video`, `options.asynchronousDecompression` e `options.hardwareDecode` estão ativos e a `DecompressionSession` é criada com sucesso, retorna `VideoToolboxDecode`; caso contrário cai para `FFmpegDecode` (decodificação por software) — fallback automático.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:85` e `:477` — flag pública `hardwareDecode` (default `true`, estático `KSOptions.hardwareDecode`), configurável por instância/globalmente.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:314-316` — lógica que desativa `hardwareDecode` em certos casos (ex.: filtros de deinterlace) e escolhe o filtro `yadif_videotoolbox` vs `yadif` conforme o modo.
- `Sources/KSPlayer/MEPlayer/MEPlayerItemTrack.swift:160` — checagem `if decoder is VideoToolboxDecode` em outro ponto do pipeline (tratamento específico para frames vindos do VideoToolbox, ex. pixel buffer/hardware path).
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift`, `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift`, `Sources/KSPlayer/Metal/PixelBufferProtocol.swift`, `Sources/KSPlayer/MEPlayer/Resample.swift` — pontos auxiliares que referenciam VideoToolbox (formatDescription do asset track, extensões de pixel buffer compatíveis com Metal/CVPixelBuffer vindo do hardware, resample considerando path VT).
- `Demo/demo-iOS/demo-iOS/AppDelegate.swift`, `Demo/SwiftUI/Shared/MovieModel.swift` — uso/menu de demo que expõe a opção de hardware decode.

## Como funciona

O pipeline de decodificação de vídeo escolhe o decoder em `SyncPlayerItemTrack.makeDecode(assetTrack:)` (`MEPlayerItemTrack.swift:300`). Se `KSOptions.hardwareDecode` (default true) e `asynchronousDecompression` estiverem habilitados, tenta construir uma `DecompressionSession` real usando a API pública do VideoToolbox (`VTDecompressionSessionCreate`), configurando o `pixelFormatType` do asset track, compatibilidade com Metal e propriedades de HDR/cor. Se a criação da sessão tiver sucesso, o decoder usado passa a ser `VideoToolboxDecode`, que para cada `Packet` do FFmpeg monta um `CMSampleBuffer` (convertendo Annex-B para length-prefixed quando necessário) e chama `VTDecompressionSessionDecodeFrame` de forma assíncrona, produzindo `VideoVTBFrame` com o `CVImageBuffer` decodificado por hardware. Há tratamento de erros de sessão inválida/decoder malfuncionando com reconfiguração automática da sessão (útil no ciclo background→foreground do tvOS/iOS), e fallback automático para `FFmpegDecode` (software, via libavcodec) caso a criação da `DecompressionSession` falhe ou as flags estejam desligadas. O suporte cobre iOS/tvOS/macOS via `#if canImport(VideoToolbox)`.

## O que falta

N/A — a feature está implementada de ponta a ponta (criação de sessão, decodificação assíncrona, fallback para software, tratamento de erros/reconfiguração, e integração com o restante do pipeline de renderização via Metal/CVPixelBuffer).
