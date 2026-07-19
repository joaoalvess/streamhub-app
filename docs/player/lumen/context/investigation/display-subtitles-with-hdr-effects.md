## Status

Ausente.

## Evidência

- Todas as referências a HDR no código GPL dizem respeito ao vídeo, não às legendas:
  - `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:47,52-135` — enum `DynamicRange` (sdr/hdr10/hlg/dolbyVision), `hdrMode`, `availableHDRModes`.
  - `Sources/KSPlayer/AVPlayer/KSOptions.swift:352,405-417` — seleção de `dynamicRange`/`preferedDynamicRange` para o player de vídeo.
  - `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift:244-245` — detecção de conteúdo HDR10 via `bitDepth`/`transferFunction`.
  - `Sources/KSPlayer/MEPlayer/Model.swift:444,455,488` — construção de `CAEDRMetadata.hdr10(...)` para o frame de vídeo.
  - `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:102-105` — leitura de side data `AV_FRAME_DATA_DYNAMIC_HDR_PLUS`/`_VIVID` do FFmpeg (metadados HDR dinâmicos do vídeo).
  - `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:143` — `kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata` no VideoToolbox.
  - `Sources/KSPlayer/Core/Utility.swift:276-283` — extensão de `AVPlayer.HDRMode`.
- Pipeline de legendas não tem nenhuma menção a HDR/EDR/colorSpace/toneMap:
  - `Sources/KSPlayer/Subtitle/KSSubtitle.swift`, `KSParseProtocol.swift`, `SubtitleDataSouce.swift`, `AudioRecognize.swift` — parsing/gerenciamento de texto de legenda, sem qualquer campo de cor HDR ou metadata associada.
  - `rg -n "colorSpace|CGColorSpace|EDR|extendedRange|edrMetadata|CAEDRMetadata|toneMap" Sources/KSPlayer/Subtitle Sources/KSPlayer/Core/PlayerView.swift Sources/KSPlayer/Video/*.swift` retornou vazio.

## O que falta

Não há base nenhuma para este recurso — é uma implementação do zero. Um ponto de partida real precisaria:

1. Um renderer de legenda que desenhe em compositing com o vídeo usando o mesmo `CAEDRMetadata`/colorspace do frame de vídeo (hoje as legendas são texto simples via `NSAttributedString`/`UILabel`/`CALayer` fora do pipeline de cor do vídeo — não há evidência de overlay via `CVPixelBuffer`/Core Image).
2. Extensão do enum `DynamicRange` (`PlayerDefines.swift:44-96`) ou de uma opção nova em `KSOptions` para permitir que a legenda "herde" o brilho/gamut HDR (ex.: renderizar texto com luminância acima de 100 nits, ou aplicar tone mapping inverso para casar com o EDR do stream).
3. Onde tocar: `Sources/KSPlayer/Subtitle/KSSubtitle.swift` (modelo/estilo de legenda), o código de overlay em `Sources/KSPlayer/Video/*.swift` / `Sources/KSPlayer/Core/PlayerView.swift` (onde a camada de legenda é composta sobre o vídeo), e possivelmente `Sources/KSPlayer/MEPlayer/Model.swift` para expor o `CAEDRMetadata` do frame atual para o subsistema de legendas consumir.

Nada disso existe hoje nem como esboço/flag desativada — é recurso ausente por completo no fork GPL.
