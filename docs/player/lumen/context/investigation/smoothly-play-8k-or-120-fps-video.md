## Status

Parcial

## Evidência

- `Sources/KSPlayer/AVPlayer/KSOptions.swift:477` — `static var hardwareDecode = true` (decodificação por hardware via VideoToolbox habilitada por padrão).
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift:137` — criação de `VTDecompressionSession` genérica (sem tuning de resolução/perfil específico para 8K).
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:40-51` — propriedade `fps` observada; ao mudar, recalcula `preferredFramesPerSecond` e ajusta `displayLink.preferredFrameRateRange = CAFrameRateRange(minimum:, maximum: 2*preferred, preferred:)` (iOS/tvOS) ou `preferredFramesPerSecond` (fallback), permitindo acompanhar taxas de quadro altas (ex.: 120fps) num display ProMotion.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:60-91` — `CADisplayLink` real (`displayLink.add(to: .main, forMode: .common)`), disparando `renderFrame` a cada vsync.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:368-441` — implementação própria de `CADisplayLink` para macOS usando `CVDisplayLink`, com o mesmo papel de sincronismo de quadro.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:181` — `fps = frame.fps` atualizado por frame decodificado, disparando o ajuste do display link.
- `Sources/KSPlayer/MEPlayer/Model.swift:89-137,444-455` — mapeamento completo de color space/HDR (BT.2020, PQ, HLG, HDR10 `CAEDRMetadata`), necessário para "8K"/HDR moderno, mas não relacionado a performance/frame-rate em si.
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:102-105` — leitura de side data `AV_FRAME_DATA_DYNAMIC_HDR_PLUS`/`AV_FRAME_DATA_DYNAMIC_HDR_VIVID` (HDR10+/HDR Vivid), mas o valor lido (`data`) não é usado além de decodificado (variável sem uso posterior visível nesse trecho).
- `Sources/KSPlayer/AVPlayer/KSOptions.swift:48` — `lowres` (downscale de decodificação FFmpeg) existe como opção, mas não há lógica automática que a ative para conteúdo 8K quando o hardware não acompanha.
- Nenhuma ocorrência de "8K", "7680", limite de resolução, contagem de threads de decodificação (`thread_count`), nem qualquer branch condicional por capacidade do dispositivo (ex.: checar se o Apple TV/iPhone suporta decode HW de determinada resolução/fps antes de tentar reproduzir) em todo o pacote (`rg` não retornou nada para esses termos).

## Como funciona (o que existe)

O player decodifica via VideoToolbox por hardware (`VideoToolboxDecode.swift`) quando `hardwareDecode == true` (padrão), entregando `CVPixelBuffer`s com metadata de color space/HDR anexada (`Model.swift`, `PixelBufferProtocol.swift`). A camada de apresentação (`MetalPlayView.swift`) usa um `CADisplayLink` (iOS/tvOS) ou uma implementação própria via `CVDisplayLink` (macOS) que é realimentado a cada frame decodificado: ao detectar mudança no `fps` do vídeo, recalcula a faixa de frame rate preferida (`CAFrameRateRange`), permitindo que o sistema operacional sincronize o refresh do display (ex.: 120Hz em telas ProMotion) com o conteúdo. Esse mecanismo é genérico — funciona para qualquer fps reportado pelo `VideoVTBFrame`, incluindo taxas altas, e para qualquer resolução que o decoder de hardware aceite, incluindo 8K, desde que o SoC/GPU subjacente suporte.

Não existe, porém, nenhum código dedicado a: (1) detectar a capacidade do hardware (ex.: Apple TV 4K de geração X pode não suportar decode 8K ou HDR de determinado codec) e adaptar o comportamento (fallback de resolução, downscale via `lowres`, redução de fps), (2) contagem/otimização de threads de decodificação por software para cenários de alta resolução quando VideoToolbox não está disponível ou falha, ou (3) qualquer teste/comentário no repositório mencionando 8K ou 120fps como cenário validado.

## O que falta

Para chegar a "presente" (reprodução fluida validada de 8K/120fps ponta a ponta), faltaria:
- Lógica de fallback/adaptação de capacidade: verificar antes (ou detectar falha) se `VTDecompressionSession` suporta a resolução/fps/perfil do conteúdo e, se não, aplicar `KSOptions.lowres` ou trocar para decodificação por software com `thread_count` ajustado (`KSOptions.swift` seria o ponto natural, perto de `hardwareDecode`).
- Ajuste de buffer/pipeline para taxas de quadro muito altas: os buffers de frame (`videoFrameMaxCount`, `CircularBuffer.swift`) e o cálculo de sincronismo (`videoClockSync` em `KSOptions.swift:359`) usam `fps` diretamente, mas não há teste/tuning que comprove estabilidade em 120fps — seria necessário instrumentar e validar empiricamente.
- Qualquer sinalização de UI/telemetria (ex.: indicar ao usuário que o dispositivo não suporta e vai fazer downscale), inexistente hoje.
- Testes ou arquivos de amostra 8K/120fps no repositório para validar a claim — não encontrados.

Em suma, a base técnica (hardware decode + display link dinâmico + pipeline HDR) é a mesma usada por soluções comerciais para esse recurso, mas não há nenhuma adaptação específica, teste ou salvaguarda para os casos extremos (8K, 120fps) — por isso o status é parcial, não presente.
