## Status

Parcial (esboço morto — parsing existe mas não é consumido em nenhum lugar).

## Evidência

- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:102-103` — branch `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` faz o rebind do side data FFmpeg para `AVDynamicHDRPlus` e atribui a uma constante local `data`, mas **nunca usa `data`** depois disso (nenhuma atribuição a frame/struct de saída).
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:104-105` — o mesmo padrão se repete para `AV_FRAME_DATA_DYNAMIC_HDR_VIVID` (HDR Vivid, formato chinês concorrente), também descartado.
- Comparar com o caminho que *funciona*: `FFmpegDecode.swift:106-119` (`AV_FRAME_DATA_MASTERING_DISPLAY_METADATA`) e o bloco de `ContentLightMetadata`/`AmbientViewingEnvironment` alimentam `displayData`/`contentData`/`ambientViewingEnvironment`, que em `FFmpegDecode.swift:144-145` são agregados em `videoFrame.edrMetaData = EDRMetaData(...)`. Esse é o único metadado HDR (estático, HDR10 "clássico") que efetivamente chega ao frame.
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:94-100` — Dolby Vision (`AV_FRAME_DATA_DOVI_RPU_BUFFER`, `AV_FRAME_DATA_DOVI_METADATA`) segue o mesmo padrão de stub: dados extraídos (`header`, `mapping`, `color`) mas não propagados (há até uma linha comentada `// frame.corePixelBuffer?.transferFunction = ...`).
- `rg` não encontra `AVDynamicHDRPlus`/`DYNAMIC_HDR_PLUS`/"hdr10+" em nenhum outro arquivo do pacote — não há tipo de struct Swift equivalente a `EDRMetaData` para metadata dinâmico, nem uso em `MetalPlayView.swift`, `PixelBufferProtocol.swift`, `KSOptions.swift` ou no pipeline Metal/shader.
- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:49-133` — o enum de modos HDR (`hdr10`, `hlg`, `dolbyVision`) não tem caso para HDR10+; a dinâmica de tone-mapping é tratada apenas como Dolby Vision vs. estático.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:255` (comentário) menciona que `AVSampleBufferDisplayLayer` "suporta HDR10+", mas é só um comentário de justificativa de escolha de camada de renderização — não há código que efetivamente entregue metadata dinâmico a essa layer.

## Como funciona

Não se aplica de ponta a ponta — não há fluxo funcional. O que existe é: o demuxer/decoder FFmpeg já entrega o side data `AV_FRAME_DATA_DYNAMIC_HDR_PLUS` quando o stream tem HDR10+ (isso vem de baixo, da libavutil/libavcodec), e o KSPlayer detecta esse side data e o desempacota para a struct C `AVDynamicHDRPlus`. Isso é o único "hook" presente — o branch existe e seria o ponto de entrada correto. Mas o resultado do parsing não sai desse escopo: não é anexado a `VideoVTBFrame`/`videoFrame`, não populamos nenhum `EDRMetaData`-like struct dinâmico, e não há ponte para AVFoundation/CoreVideo (como `CVBufferSetAttachment` de `kCVImageBufferAlternateTransferFunctionKey` ou os metadados dinâmicos exigidos por HDR10+ no macOS/tvOS via `CMFormatDescription`/`AVSampleBufferDisplayLayer`).

## O que falta

Para tornar isso "presente", seria necessário:
1. Definir um tipo Swift para metadado dinâmico (análogo a `EDRMetaData` em algum arquivo de `Model.swift`/`MediaPlayerProtocol.swift`), carregando os campos de `AVDynamicHDRPlus` (curvas de tone-mapping por frame, países de `itu_t_t35`, etc.).
2. Popular esse novo campo em `VideoVTBFrame`/`videoFrame` dentro do bloco em `FFmpegDecode.swift:102-103`, do mesmo jeito que `edrMetaData` é setado em `FFmpegDecode.swift:145`.
3. Propagar o metadado por frame até o ponto de apresentação: via `CMSampleBuffer` attachments (`kCMFormatDescriptionExtension_...`/`kCVImageBufferContentLightLevelInfoKey` dinâmico não existe nativamente — HDR10+ dinâmico no Apple stack normalmente é feito criando um `CMFormatDescription` com extensão dinâmica por frame, ou fazendo tone-mapping manual antes do render) — isso tocaria `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift` e `Sources/KSPlayer/Metal/PixelBufferProtocol.swift`/`MetalPlayView.swift` (pipeline Metal), pois hoje só HDR10 estático e Dolby Vision (via decode DOVI RPU) têm caminho de exibição.
4. Adicionar um caso no enum de `DynamicRange`/HDR mode em `PlayerDefines.swift:49-133` e refletir isso em `KSOptions.updateVideo(refreshRate:isDovi:formatDescription:)` (`KSOptions.swift:339-351`), que hoje só decide `dynamicRange` olhando para `.dolbyVision`.
5. Implementar o algoritmo de tone-mapping por frame usando as curvas dinâmicas (isso é o que efetivamente diferencia HDR10+ de HDR10 estático) — nenhum código de tone-mapping dinâmico existe no repositório; o shader Metal atual (visto em `MetalPlayView.swift`/`PixelBufferProtocol.swift`) não referencia curvas HDR10+ em nenhum ponto.

Em resumo: o parsing bruto do side data está ali como esqueleto (provavelmente copiado de um branch upstream do KSPlayer/ffmpeg-kit que lida com múltiplos tipos de side data), mas termina em uma variável local descartada — não há tipo de dado de destino, não há propagação para o pipeline de renderização, e não há tone-mapping dinâmico implementado.
