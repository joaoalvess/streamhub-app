# Video upscaling

## Status
Ausente.

## Evidência
- `Sources/KSPlayer/MEPlayer/Resample.swift:25` — `VideoSwscale: FrameTransfer` usa `libswscale`, mas apenas para conversão de pixel format (ex. YUV420P → BGRA), não para reescalar/upscale de resolução.
- `Sources/KSPlayer/MEPlayer/Resample.swift:55` — `sws_scale_frame(imgConvertCtx, outFrame, avframe)`.
- `Sources/KSPlayer/MEPlayer/Resample.swift:166` — `sws_scale(...)` no caminho de conversão para `CVPixelBuffer`.
- `Sources/KSPlayer/Metal/Shaders.metal:31-103` — todos os fragment shaders (`displayTexture`, `displayYUVTexture`, `displayNV12Texture`, `displayYCCTexture`) fazem apenas conversão de colorspace (YUV/NV12/YCC → RGB) para exibição; nenhum kernel de upscaling, sharpening ou super-resolução.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift:28-58` — pipeline de vídeo usa `AVSampleBufferDisplayLayer` e `CADisplayLink`; não há passo de reescala de qualidade.
- `Sources/KSPlayer/AVPlayer/KSOptions.swift` — nenhuma propriedade/flag relacionada a upscale, super-resolution, ou qualidade de escala.
- Busca ampla no repositório (`rg -in "upscal|super.?resolution|MPS|MetalPerformanceShaders|CIFilter|lanczos|bicubic|sharpen|nnedi|anime4k"`) não retornou nenhuma outra ocorrência relevante além do uso trivial de `sws_scale` para conversão de formato.

## O que falta
Não existe nenhuma base/esboço para upscaling — seria uma feature nova do zero. Uma implementação real precisaria:

1. Um pipeline de pós-processamento de textura no Metal (novo arquivo `.metal` com kernel de upscaling — ex. Lanczos, bicubic, ou um modelo de super-resolução via Core ML/MPS), inserido entre a textura decodificada e o `MTLRenderPipelineState` atual em `Sources/KSPlayer/Metal/MetalRender.swift`.
2. Extensão de `KSOptions` (`Sources/KSPlayer/AVPlayer/KSOptions.swift`) com uma flag de configuração (ex. `videoUpscaleMode`/`videoQuality`) para o usuário escolher o algoritmo/ativar o recurso.
3. Ajuste em `MetalPlayView.swift` (Sources/KSPlayer/MEPlayer/MetalPlayView.swift) para rotear a textura pelo novo passo de upscaling antes de compor no `displayLayer`, ou substituição do caminho `AVSampleBufferDisplayLayer` por renderização Metal direta quando o upscaling estiver ativo (hoje o display via `AVSampleBufferDisplayLayer` não permite pós-processamento arbitrário de frame).
4. Possivelmente usar `MPSImageLanczosScale`/`MPSImageBicubicScale` (Metal Performance Shaders) como caminho mais simples, ou um modelo Core ML para super-resolução mais avançada — nenhuma dessas dependências está referenciada no projeto hoje.
