# Exec [[dv-fase0]] — Dolby Vision Fase 0: correção de cor P5 no pipeline Metal

**Branch:** `task/dv-fase0` (worktree a partir de `1b8b46f`, main intocado)
**Status:** implementado e commitado; validação em device pendente (dono)

## Commits

| Hash | Mensagem |
|---|---|
| `be92bc8` | fix: use blue primary x coordinate in mastering display metadata |
| `fdf9d57` | fix: return PQ transfer function for Dolby Vision dynamic range |
| `0f62df5` | fix: correct IPT-PQc2 conversion math in displayYCCTexture |
| `e96cd4f` | feat: route Dolby Vision profile 5 frames to the IPT Metal pipeline |
| `0c8c14f` | fix: apply IPT colorimetry on the VideoToolbox decode path (review) |

## O que foi feito

1. **Profile-awareness**: `dovi.dv_profile`/`dv_bl_signal_compatibility_id` agora são lidos. Novo `DOVIDecoderConfigurationRecord.isIPTPQc2` (`dv_profile == 5 && dv_bl_signal_compatibility_id == 0`) diferencia P5 (base layer IPT-PQc2) de P8.x/P7 (base layer HDR10/SDR/HLG compatível).
2. **Sinal IPT até o render**: `PixelBufferProtocol` ganhou `isIPT: Bool` — no `CVPixelBuffer` via attachment custom `KSPlayerIPTContent` (`.shouldNotPropagate`); no `PixelBuffer` (sw) como stored var. Setado em `VideoSwresample.change` (caminho FFmpeg/hwaccel, o default) e em `VideoToolboxDecode` (caminho async, raro).
3. **Roteamento P5 → shader IPT**: `MetalRender.draw` passa `isIPT` a `DisplayEnum.pipeline(planeCount:bitDepth:isIPT:)`; `PlaneDisplayModel` ganhou os pipelines `ycc` (`displayYCCTexture`, biplanar/P010 do hwaccel) e `yccPlanar` (novo `displayYCCPlanarTexture`, 3 planos yuv420p10le do decode sw), selecionados apenas quando `isIPT && bitDepth == 10` — todo o resto segue nos pipelines YUV atuais.
4. **Bypass do displayLayer para P5**: em `MetalPlayView.draw`, frame com `isIPT` vai para o caminho Metal mesmo com `isUseDisplayLayer()` true — o `AVSampleBufferDisplayLayer` não tem como converter IPT (é a origem do tint roxo/verde dos issues upstream #771/#348 na config default). P8.1/HDR10/SDR continuam indo pro displayLayer como antes.
5. **Shader `displayYCCTexture` consertado** (estava órfão E quebrado):
   - matriz `ipt2lms` tinha divisão inteira (`799/8192` == 0 em MSL) e estava transposta (linhas escritas como colunas); reescrita com os valores decimais do libplacebo (`pl_ipt_ipt2lms`: col1 = 0.0975/-0.1139/0.0326, col2 = 0.2052/0.1332/-0.6769) — que batem com as frações originais 799/8192 etc.;
   - aplicação de `leftShift` (frames sw 10-bit LSB) e centragem de croma `ipt.yz -= 0.5` (offset neutro; seguindo o libplacebo, DV bypassa a normalização limited-range — sem expansão 255/219);
   - `shaderDeLinearize` (OETF PQ) tinha sinal errado no numerador: `(c1 - c2*Y^m1)` → corrigido para `(c1 + c2*Y^m1)` (ST 2084; como estava, produzia NaN);
   - `lms2rgb` já estava correta (LMS→RGB BT.2020 com crosstalk 2% desfeito, igual à referência).
6. **Metadados estáticos do frame P5**: `VideoSwresample.change` força nos frames IPT `yCbCrMatrix/colorPrimaries = ITU_R_2020`, `transferFunction = SMPTE_ST_2084_PQ` e `colorspace = itur_2100_PQ` — P5 costuma sinalizar colorimetria unspecified no VUI, o que caía no default sRGB do `KSOptions.colorSpace` e quebrava o EDR do `CAMetalLayer`.
7. **`DynamicRange.transferFunction`**: `.dolbyVision` agora retorna `kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ` (antes HLG). Único consumidor: pixel transfer da sessão VT (`VideoToolboxDecode.swift:148`).
8. **Bug do primário azul**: `FFmpegDecode` usava `display_primaries.2.1.num` para `display_primaries_b_x` (x == y do azul); corrigido para `2.0` — afeta o `EDRMetaData` estático de HDR10 e P8.

## Arquivos tocados (paths relativos ao pacote)

- `Sources/KSPlayer/AVPlayer/MediaPlayerProtocol.swift` — extensão `DOVIDecoderConfigurationRecord.isIPTPQc2`.
- `Sources/KSPlayer/AVPlayer/PlayerDefines.swift` — `DynamicRange.transferFunction`: `.dolbyVision` → PQ.
- `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift` — fix primário azul (linha 113); passa `isIPT` ao `VideoSwresample`.
- `Sources/KSPlayer/MEPlayer/Resample.swift` — `VideoSwresample` ganhou `isIPT` (default `false`, demais call sites intocados); marca o pixel buffer e força colorimetria 2020/PQ em frames IPT.
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift` — marca `isIPT` no `imageBuffer` quando o track é P5.
- `Sources/KSPlayer/MEPlayer/MetalPlayView.swift` — frames IPT nunca vão pro `AVSampleBufferDisplayLayer` (uma condição a mais na linha 185).
- `Sources/KSPlayer/Metal/PixelBufferProtocol.swift` — `isIPT` no protocolo + implementações (attachment no `CVPixelBuffer`, stored no `PixelBuffer`).
- `Sources/KSPlayer/Metal/Shaders.metal` — `displayYCCTexture` corrigido; `shaderDeLinearize` corrigido; novo `displayYCCPlanarTexture` (3 planos).
- `Sources/KSPlayer/Metal/DisplayModel.swift` — pipelines `ycc`/`yccPlanar`; `pipeline(planeCount:bitDepth:isIPT:)` no `DisplayEnum` e `PlaneDisplayModel`.
- `Sources/KSPlayer/Metal/MetalRender.swift` — passa `pixelBuffer.isIPT` na seleção de pipeline.

## Decisões

- **Detecção conservadora**: `isIPTPQc2` exige `dv_profile == 5` E `compat_id == 0` — P7 (compat 1/6) e P8 (1/2/4) nunca entram no caminho IPT, garantindo o critério "sem regressão de P8.1/HDR10".
- **Referência de cor = libplacebo**: sem expansão limited-range e sem dobra de croma (a matriz comentada no shader com valores 2x foi mantida como comentário, mas não é o que o libplacebo/mpv fazem); croma centrado em exatamente 0.5.
- **YCC só com bitDepth == 10**: evita mismatch de pixel format do render pass (pipelines YCC são criados com `bgr10a2Unorm`); P5 é sempre 10-bit na prática.
- **Bypass do displayLayer em vez de override de `isUseDisplayLayer`**: a decisão é por frame (`isIPT`), não por config — P8.1 continua no displayLayer (que mostra a base HDR10 corretamente e suporta HDR10+).
- **VR/sphere fora do escopo**: `SphereDisplayModel` mantém os pipelines YUV (DV em 360° não é caso real).
- **Sem RPU dinâmico**: isto é correção de cor estática (Fase 0). O RPU continua descartado em `FFmpegDecode.swift:94-105` — não confundir com a entrega de [[dv-nativo]]/Fase 1.

## Revisão (lane dv-fase0)

- Diff completo auditado contra a base `1b8b46f`: matrizes `ipt2lms`/`lms2rgb` conferidas contra o libplacebo (colunas MSL batem com as linhas de `pl_ipt_ipt2lms`/`pl_ipt_lms2rgb`), OETF/EOTF PQ conferidas contra ST 2084, `leftShift` correto nos dois caminhos (hw P010 ×1, sw LSB ×64), nenhum call site quebrado, nenhum force unwrap/`try!`/`as!` novo, P8.1/HDR10/SDR intocados.
- **Correção aplicada (`0c8c14f`)**: o caminho async do `VideoToolboxDecode` marcava `isIPT` mas não forçava a colorimetria 2020/PQ — frame P5 (VUI unspecified) chegaria ao `CAMetalLayer` com colorspace nil/sRGB, quebrando o EDR nesse caminho. Extraído `PixelBufferProtocol.applyIPTPQc2Colorimetry()` e usado no `VideoSwresample.change` e no callback do VT.
- Shaders.metal compilado com `xcrun -sdk macosx metal -c`: limpo.

## Pendências

- **Validação visual em device** (dono): não rodei build (regra do repo); todos os .swift passaram em `xcrun swiftc -parse`. O `.metal` foi compilado na revisão com `xcrun -sdk macosx metal -c` — sem erros; o risco de falha do `makeDefaultLibrary` em runtime está descartado.
- **Sem amostras no repo**: validação depende de P5 (`dvhe.05.06`) e P8.1 reais (risco já mapeado no roadmap; [[sample-library]]).
- **Aproximação estática**: sem o reshape polinomial do RPU o tone/saturação do P5 fica próximo mas não bit-exato ao pipeline DV real; é o esperado da Fase 0.
- **`MediaPlayerTrack.dynamicRange`** continua reportando `.dolbyVision` para qualquer track com `dovi` (inclusive P8) — comportamento preservado; refinamento por perfil fica para a Fase 1.
- Nota operacional: durante a sessão o disco da máquina bateu 100% (ENOSPC geral, ~118 MB livres); o macOS purgou caches sozinho e a task continuou. Vale checar o que está enchendo o disco.

## Como o dono valida no Apple TV

1. Apontar o app para a branch `task/dv-fase0` do pacote Player (worktree em `/private/tmp/.../wt-dv-fase0` — efêmero; a branch está no `.git` do repo principal: `git -C ~/Developer/StreamHub/Player branch --contains e96cd4f`).
2. Tocar uma amostra **P5** (`dvhe.05.06`, MKV via KSMEPlayer): a imagem deve sair com cores normais (sem roxo/verde). No log deve aparecer `[video] CAMetalLayer colorspace` com `itur_2100_PQ` — confirma que o frame foi pro caminho Metal/YCC e não pro displayLayer.
3. Tocar uma amostra **P8.1**: deve continuar idêntica a antes (base HDR10 via displayLayer; TV entra em modo HDR).
4. Tocar **HDR10 puro e SDR**: sem mudança visual (regressão zero esperada — nenhum caminho não-DV foi alterado).
5. Opcional (caminho sw): forçar `options.hardwareDecode = false` num P5 e conferir que a cor continua correta (exercita `displayYCCPlanarTexture` + leftShift).
