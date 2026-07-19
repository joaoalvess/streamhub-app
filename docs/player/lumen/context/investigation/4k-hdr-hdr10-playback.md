# 4K/HDR/HDR10 playback

## Status

Presente. O fork GPL implementa o pipeline completo de detecção, decodificação e apresentação de conteúdo HDR (HDR10, HLG e Dolby Vision com fallback para HDR10), tanto no caminho de decode via hardware (VideoToolbox) quanto no de apresentação (Metal/EDR e AVDisplayManager no tvOS). 4K em si não depende de código específico (é apenas resolução do stream, suportada pelo pipeline FFmpeg/VideoToolbox normal).

## Evidência

- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:45-127` — `enum DynamicRange` (sdr/hdr10/hlg/dolbyVision), mapeamento para `AVPlayer.HDRMode`, `availableHDRModes` (checa `AVPlayer.availableHDRModes` no tvOS/iOS e `maximumPotentialExtendedDynamicRangeColorComponentValue` no macOS), e propriedades `colorPrimaries`/`transferFunction`/`yCbCrMatrix` por dynamic range (BT.2020, PQ/SMPTE ST.2084, HLG).
- `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:233-234` — extrai `color_primaries`/`color_trc` do `codecpar` do FFmpeg e monta `kCVImageBufferColorPrimariesKey`/`kCVImageBufferTransferFunctionKey` para o `CMFormatDescription` usado no VideoToolbox.
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:109-149` — `DecompressionSession` cria a sessão VideoToolbox, ativa `kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata` (iOS/tvOS 14+/macOS 11+) e configura `kVTDecompressionPropertyKey_PixelTransferProperties` com primaries/transferFunction/matrix de destino conforme `options.availableDynamicRange(nil)`.
- `Sources/KSPlayer/MEPlayer/Resample.swift:131-141` — no caminho de decode por software, copia `color_primaries`/`color_trc` do `AVFrame` para o pixel buffer de saída via `KSOptions.colorSpace`.
- `Sources/KSPlayer/Metal/PixelBufferProtocol.swift:98-191` — `CVPixelBuffer` extension expõe `colorPrimaries`/`colorspace`/`transferFunction` lendo/escrevendo attachments do CVImageBuffer; `BufferModel` (struct usado no pipeline de render) computa `colorspace` a partir do `AVFrame` via `KSOptions.colorSpace(ycbcrMatrix:transferFunction:)`.
- `Sources/KSPlayer/MEPlayer/Model.swift:89-135` — `KSOptions.colorSpace(ycbcrMatrix:transferFunction:)` e `colorSpace(colorPrimaries:)` mapeiam para `CGColorSpace` corretos: `itur_2100_PQ`/`itur_2020_PQ` (HDR10, com fallbacks por versão de OS), `itur_2100_HLG` (HLG), `displayP3_PQ` (DCI-P3).
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:277-283` — aplica o `colorspace` calculado no `CAMetalLayer` (`metalLayer.colorspace = colorspace`), habilitando EDR/wide color no caminho de render Metal.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:255` (comentário) — nota de que `AVSampleBufferDisplayLayer` é o caminho recomendado por suportar HDR10+.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:346-356` — em tvOS/xrOS, ajusta `AVDisplayCriteria.preferredDisplayCriteria` do `AVDisplayManager` para casar o modo de exibição da TV com o dynamic range do conteúdo (com fallback dolbyVision→hdr10 quando necessário).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:404-421` — `availableDynamicRange(_:)` decide entre o dynamic range preferido pelo usuário (`destinationDynamicRange`) e o suportado pelo display (`AVPlayer.availableHDRModes`), com fallback para SDR ou para o dynamic range do conteúdo.
- `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:210-211` — protocolo expõe `colorSpace` computado a partir de `yCbCrMatrix`/`transferFunction` do track, reaproveitando `KSOptions.colorSpace`.

## Como funciona

1. Ao abrir o arquivo, `FFmpegAssetTrack` lê os metadados de cor do stream (`color_primaries`, `color_trc` do `AVCodecParameters` do FFmpeg) e os injeta no `CMFormatDescription` usado para criar a sessão de decode.
2. No decode por hardware (`VideoToolboxDecode.swift`), a `DecompressionSession` é criada com `kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata` ativado (propaga metadados HDR10 dinâmicos por frame) e com `PixelTransferProperties` configuradas para o dynamic range de destino calculado por `KSOptions.availableDynamicRange`, que consulta `AVPlayer.availableHDRModes` (ou o suporte do display no macOS) e decide entre HDR10/HLG/Dolby Vision (rebaixado a HDR10)/SDR.
3. No decode por software (`Resample.swift`), o mesmo tipo de metadado (`color_primaries`/`color_trc` do `AVFrame`) é propagado para o `CVPixelBuffer` de saída via `KSOptions.colorSpace`.
4. Cada `CVPixelBuffer` carrega o `CGColorSpace` correto (BT.2020 PQ para HDR10, BT.2100 HLG para HLG, DCI-P3 PQ quando aplicável) através dos accessors em `PixelBufferProtocol.swift`.
5. No caminho de render Metal (`MetalPlayView.swift`), o `colorspace` do pixel buffer é aplicado diretamente ao `CAMetalLayer`, habilitando o pipeline EDR (Extended Dynamic Range) do sistema para apresentar o conteúdo HDR corretamente na tela.
6. Em tvOS, adicionalmente, `KSOptions` ajusta o `AVDisplayCriteria` do `AVDisplayManager` para fazer a Apple TV trocar o modo de saída de vídeo (refresh rate + dynamic range) casando com o conteúdo, replicando o comportamento nativo esperado de players tvOS de referência (ex.: Infuse).
7. 4K não tem tratamento especial — é resolução normal suportada pelos mesmos caminhos de decode (VideoToolbox HW decode aceita até a resolução que o hardware suportar); não há cap de resolução no código revisado.

## O que falta

Não aplicável — feature presente e funcional de ponta a ponta (extração de metadados → decode → colorspace → apresentação/display mode switching). Nenhuma lacuna estrutural identificada nos arquivos revisados.
