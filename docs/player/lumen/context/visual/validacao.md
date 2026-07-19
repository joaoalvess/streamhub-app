# Validação — Reforma da UI tvOS do player (etapa 4/4)

Auditoria do diff da etapa 3 (`context/visual/execucao.md`) contra o plano
(`context/visual/plano.md`). Método: leitura integral dos 4 arquivos novos de
`Sources/KSPlayer/SwiftUI/TVOS/`, revisão do `git diff` dos arquivos editados
(`KSVideoPlayerView.swift`, `Slider.swift`, `KSVideoPlayer.swift`, `KSOptions.swift`,
`KSVideoPlayerViewBuilder.swift`), verificação símbolo a símbolo das APIs consumidas
pelas views novas, conferência de assinatura no SDK e `swiftc -parse` nos três targets.
Nenhum build foi rodado (regra do repo).

## Veredito

**APROVADO com 1 correção aplicada nesta etapa e pendências conhecidas.** Todos os
itens do plano (1-10) estão implementados ou explicitamente adiados conforme o próprio
plano permitia (P2 de FF/REW contínuo). Não foram encontrados: símbolos inexistentes,
assinaturas erradas, branches de plataforma faltando, force unwraps introduzidos, nem
efeitos de foco manuais (scale/sombra) em botões. A validação dos critérios 2 e 3 do
plano (comparação visual lado a lado e roteiro de gestos no Siri Remote) **exige
dispositivo/simulador e fica com o dono do projeto** — builds, capturas e execução real
são dele, conforme o fluxo de trabalho deste repo.

## Correção aplicada nesta etapa

1. **Glifo de skip saiu do fluxo de layout** —
   `Sources/KSPlayer/SwiftUI/TVOS/TVControlsOverlayView.swift:47-52`. Antes, o hint era
   inserido como linha do `VStack` (`if let skipHint { skipHintView(...) }` entre a
   title view e a transport bar), fazendo título e chips pularem verticalmente a cada
   skip e voltarem 0.9s depois. Agora é `.overlay(alignment: .top)` ancorado na
   `TVTransportBar` — feedback aparece acima da barra no lado correspondente sem
   deslocar nenhum elemento. Posição fina a calibrar por screenshot (ver pendências).

## O que foi verificado e passou

### Compilação (estática, sem build)

- `swiftc -parse` OK para `arm64-apple-tvos16.0`, `arm64-apple-ios16.0` e
  `arm64-apple-macos13.0` em todos os arquivos criados/editados (incluindo pós-correção).
- Assinatura de Liquid Glass conferida no SDK AppleTVOS 27.0
  (`SwiftUICore.swiftinterface`): `glassEffect(_ glass: Glass = .regular, in shape: some
  Shape = DefaultGlassEffectShape())` e `Glass.clear`, ambos `@available(tvOS 26.0, *)`
  — exatamente como usados em `TVGlassMaterial.swift:13-14` sob
  `#if compiler(>=6.2)` + `if #available(tvOS 26.0, *)`.
- Init memberwise de structs com `@State private var` com valor default instanciadas de
  outro arquivo (`TVTransportBar`, `TVContentTabsView`, `MenuView`) — reproduzido em
  harness isolado com `swiftc -typecheck`: compila (o default remove a restrição de
  acesso).
- Todos os símbolos consumidos pelas views novas existem com os tipos esperados:
  `Coordinator.timemodel/state/playbackRate/isScaleAspectFill/skip(interval: Int)/
  seek(time:)/mask(show:autoHide:)` (`AVPlayer/KSVideoPlayer.swift:94-213`),
  `MediaPlayerProtocol.chapters` + `struct Chapter { start, end, title }`
  (`AVPlayer/MediaPlayerProtocol.swift:20,61-65`), `MediaPlayerTrack.dynamicRange:
  DynamicRange?` e `fieldOrder` (`MediaPlayerProtocol.swift:129,202`),
  `SubtitleInfo.subtitleID/name` (`Subtitle/KSSubtitle.swift:129-137`),
  `Int.toString(for: .minOrHour)` (`AVPlayer/PlayerDefines.swift:303`),
  `kmFormatted`/`runOnMainThread` (`Core/FoundationExtend.swift:62,80`),
  `extension Float: Identifiable` (`Core/SwiftUIExtend.swift:192`) — necessário para os
  `ForEach` de velocidade.
- Reuso do motor `TVSlide`: `TVScrubberInput` casa com o estado real de `Slider.swift`
  (init `value:bounds:onEditingChanged:`, membros internos `processView`, `value`,
  `ranges` e `onEditingChanged` mutáveis, `onDownArrow` tratado em `pressesBegan`).
- Padrões espelham código já compilado do repo (mesmo `MenuView` com `Binding`
  get/set, mesmo `ForEach(id: \.subtitleID)` de `KSVideoPlayerViewBuilder.swift:54`),
  o que reduz o risco residual do type-check completo pendente de build.

### Não-regressão de plataforma (critério 4 do plano)

- Branches iOS/macOS/xrOS de `KSVideoPlayerView.swift` intactos: `controllerView`
  não-tvOS preserva `VideoControllerView` + `VideoTimeShowView` + `.focused/.opacity/
  .padding`; skip de 15s preservado fora do tvOS (`:216,223`); `onTapGesture` de
  toggle preservado no iOS (`:270-272`). `VideoControllerView`, `VideoTimeShowView` e
  `VideoSettingView` continuam existindo (o branch tvOS interno delas vira código morto
  no tvOS, como o plano previu).
- `overlayGradient` removido sem outros consumidores (rg: zero referências).
- Fix dos swipe recognizers vive em `makeView` com guarda de identidade
  (`KSVideoPlayer.swift:169-186`), `#if canImport(UIKit)` correto para macOS;
  `resetPlayer` zera a referência. Vale para iOS por decisão de plano (correção de bug).
- API pública preservada (critério 5): inits de `KSVideoPlayerView` intocados; aditivos
  opcionais `tvPlayerMetadata(_:)`/`TVPlayerMetadata`, `KSOptions.tvSkipInterval`
  (default 10). Mudanças de visibilidade (`FocusableField`, `DynamicInfoView.dynamicInfo`,
  membros de `TVSlide`) são fileprivate/private→internal — nada público mudou.

### Checklist de paridade (critério 1 do plano) — evidências

| Item | Evidência |
|---|---|
| Anatomia §1.1-1.2: title view `.headline` + subtítulo, ícones chapados à direita em chips de material, sem `.circle.fill`, sem botão de fechar | `TVControlsOverlayView.swift:90-114,139-145` |
| Transport bar §1.2: track fina translúcida, porção branca, playhead + timestamp em scrub, tempos decorrido/−restante abaixo, slot de thumbnail | `TVTransportBar.swift:37-97` |
| Content tabs §1.3: Info/Chapters/Audio/Subtitles/Speed/Advanced; Chapters/Audio condicionais; seleção com check; ações Play from Beginning + contentMode | `TVContentTabsView.swift:46-58,100-238` |
| Materiais §2: dimming 0→0.35 + glass tvOS 26 c/ fallback `.ultraThinMaterial` | `TVControlsOverlayView.swift:67-78`; `TVGlassMaterial.swift:11-21` |
| Tipografia §3: só text styles (`.headline/.caption/.body/.callout/.title3`) + `.monospacedDigit()` nos tempos | `TVTransportBar.swift:77,96`; `TVContentTabsView.swift:111,121,156` |
| Layout §4: margens 80 laterais / 60 base; legendas sobem com a máscara | `TVControlsOverlayView.swift:64-65`; `KSVideoPlayerView.swift:82` |
| Gestos §5: skip ±`tvSkipInterval` c/ hint, select=play/pause, ↓ abre tabs (move, swipe e press na barra), ↑ pin, Back desce um nível (loading→dismiss; tabs→barra; barra→vídeo; vídeo→dismiss) | `KSVideoPlayerView.swift:129-141,175-184,261-268,275-289,361-365`; `Slider.swift:117-124` |
| Buffering §7: loading inicial preto + `ProgressView()` central sem controles; rebuffer na barra; erro com material | `KSVideoPlayerView.swift:91-98,109`; `TVTransportBar.swift:89-91` |
| Foco §8: 100% sistema (`.borderless` 17+ / `.card` 16), zero scale/sombra manual (rg confirmou) | `TVGlassMaterial.swift:24-30`; uso em `TVControlsOverlayView.swift:112`, `TVContentTabsView.swift:79` |
| Timing §9: auto-hide 5s inalterado (`animateDelayTimeInterval`), animações `.easeInOut` padrão | `Video/VideoPlayerView.swift:940`; `KSVideoPlayerView.swift:83,326` |
| Fixes de base: pan `.cancelled/.failed` restaura estado; recognizers sem acúmulo; tint vermelho removido | `Slider.swift:163-165`; `KSVideoPlayer.swift:139-151`; diff de `TVOSSlide.updateUIView` |

## Pendências confirmadas (herdadas da execução, não bloqueiam)

- **P2 do plano**: segurar ←/→ para FF/REW 2x→4x — adiamento previsto pelo plano.
- Back durante scrub não restaura a posição anterior (pesquisa §6.6).
- Depois de fechar as tabs com Back, a máscara permanece pinada até o próximo Back
  (`mask(show: true)` não limpa `isMaskPinned`; o unpin só acontece em
  `isMaskShow = false`). Corrigir pede uma API de unpin no `Coordinator` — decisão de
  design deixada para o dono.
- Foco inicial cai no primeiro chip, não no scrubber; troca de aba é por select, não
  por foco — polimento que depende de teste no aparelho.
- Checkmark da aba Audio pode ficar desatualizado até o próximo re-render.
- Constantes visuais são aproximações a calibrar por screenshot contra o player nativo:
  track 8pt, chips 64pt, gradiente 0.35, padding de legenda 200pt e a posição do glifo
  de skip no overlay da barra (correção desta etapa).
- Interação com foco não reinicia o timer de auto-hide de 5s (limitação pré-existente
  do sistema de máscara, não introduzida pela reforma).

## O que fica com o dono do projeto

A validação final em dispositivo real é do dono do projeto: build do pacote para
tvOS/iOS/macOS sem warnings novos, comparação visual lado a lado com o player nativo do
tvOS 26 (cenas: reprodução, controles visíveis, scrub pausado, tabs, buffering, erro),
roteiro de gestos completo no Siri Remote e screenshot de sanidade de iOS/macOS. Esta
etapa cobriu apenas o que é verificável estaticamente.

## Observação sobre o working tree

O working tree contém muitas modificações pré-existentes fora do escopo da reforma
(`KSAVPlayer`, `MEPlayer/*`, `Metal/*`, `Core/*`, remoção de `Utility.swift`, etc.).
O critério 4 do plano ("diff só toca arquivos da reforma") vale para o delta da etapa 3,
não para o diff total contra HEAD — essas mudanças não foram auditadas aqui.
