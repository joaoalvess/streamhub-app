# Execução — Reforma da UI tvOS do player (etapa 3/4)

Diário da implementação de `context/visual/plano.md`. Todos os paths são relativos à
raiz do repo (`/Users/joaoalves/Developer/StreamHub/Player`). Nenhum build foi rodado
(regra do repo: builds/testes são do dono do projeto); cada arquivo tocado passou por
`swiftc -parse` com targets `arm64-apple-tvos16.0`, `arm64-apple-ios16.0` e
`arm64-apple-macos13.0` — sintaxe validada nas três plataformas, type-check completo
pendente de build.

## Arquivos criados

### `Sources/KSPlayer/SwiftUI/TVOS/TVGlassMaterial.swift`
- `View.tvPlayerControlMaterial(in:)`: em tvOS 26+ aplica `glassEffect(.clear, in:)`
  (variant clear — controles sobre mídia, pesquisa §2.2); em tvOS 16-25 fallback
  `background(.ultraThinMaterial, in:)`. Guardado por `#available(tvOS 26.0, *)` e
  também `#if compiler(>=6.2)` para toolchains sem o SDK 26.
- `View.tvSystemFocusButtonStyle()`: `.buttonStyle(.borderless)` (efeito de foco do
  sistema) em tvOS 17+, fallback `.card` em tvOS 16 (`.borderless` só existe em tvOS
  a partir do 17 — conferido no SDK).
- **Assinaturas de glass conferidas no SDK AppleTVOS 27.0** (exigência do plano):
  `glassEffect(_ glass: Glass = .regular, in shape: some Shape)` e `Glass.clear`
  existem para tvOS 26+ em SwiftUICore; `GlassEffectContainer` existe mas não foi
  usado (efeitos isolados, sem necessidade de morphing entre shapes);
  `.buttonStyle(.glass)` existe mas foi preterido — usar glass no chip via
  `tvPlayerControlMaterial` + `.borderless` evita platter duplicado.

### `Sources/KSPlayer/SwiftUI/TVOS/TVTransportBar.swift`
- `TVTransportBar` (plano item 3): scrubber com track fina translúcida
  (`Capsule` branca 0.3, 8pt), porção reproduzida em branco sólido, playhead
  (4×24pt) + timestamp acompanhando o arrasto quando em scrub; `scrubPreviewSlot`
  (hoje `EmptyView`) é a âncora visual para o thumbnail do roadmap
  `progressbar-preview.md`.
- Tempos abaixo da barra: decorrido à esquerda, restante com prefixo `-` à direita,
  `.caption.monospacedDigit()` (pesquisa §3/§9 do plano).
- Spinner de rebuffer (`config.state == .buffering`) pequeno no leading da linha de
  tempos (plano item 6b — a anatomia nativa não tem botão play/pause na barra, então
  o spinner fica na própria transport bar).
- `TVScrubberInput` (`UIViewRepresentable`): reusa o motor `TVSlide` (presses
  acelerados, pan, commit em select) escondendo o `UIProgressView` interno
  (`processView.isHidden = true`) — decisão prevista no plano item 3: o
  UIProgressView virou detalhe de implementação, o visual é 100% SwiftUI por cima.
  `updateUIView` ressincroniza `value`/`ranges`/closures (bounds mudam quando a
  duração real chega).
- `Live Streaming` quando `seekable == false` (paridade com `VideoTimeShowView`).

### `Sources/KSPlayer/SwiftUI/TVOS/TVControlsOverlayView.swift`
- `TVPlayerMetadata` (público): `subtitle`, `synopsis`, `artwork` — campos opcionais
  injetáveis pelo app (análogo a `externalMetadata`), consumidos pela title view e
  pela aba Info.
- `TVSkipHint`: valor com identidade (`UUID`) para o feedback de skip; expira ~0.9s
  via `.task(id:)` no overlay (sem timers/`DispatchQueue` na view).
- `TVControlsOverlayView` (plano item 2): anatomia nativa —
  - Title view à esquerda: título `.headline` + subtítulo `.caption` secundário.
  - Ícones à direita, chapados (sem `.circle.fill`), em chips circulares de 64pt com
    `tvPlayerControlMaterial(in: Circle())`: legendas (`captions.bubble`, `MenuView`),
    áudio (`waveform`, `MenuView`, só se houver tracks), velocidade
    (`gauge.with.dots.needle.67percent`, `MenuView`) e PiP (`pip.enter`).
    **Mute e contentMode saíram da barra** (plano): contentMode virou ação da aba
    Info; mute não existe no tvOS.
  - `TVTransportBar` full-width abaixo; glifo de skip (`goforward.N`/`gobackward.N`,
    fallback sem sufixo para intervalos não padrão) exibido acima da barra no lado
    correspondente enquanto o hint está ativo.
  - `TVContentTabsView` composta DENTRO do overlay, abaixo da transport bar (decisão:
    o plano listava as tabs como view separada; compô-las no overlay garante a ordem
    visual "abaixo da barra" da pesquisa §1.3 e resolve o foco sem aninhamento de
    `.focused`).
  - Dimming: `LinearGradient` transparente → preto 0.35 (HIG, pesquisa §2.2),
    cobrindo a região dos controles; margens 80pt laterais / 60pt base (era 80/80;
    plano item 9).
  - Sem botão de fechar (Back cumpre o papel).
- Foco: o bloco header+transport bar tem `.focused(_, equals: .controller)`; as tabs
  têm `.focused(_, equals: .info)` — mesma máquina de foco do `KSVideoPlayerView`,
  recebida por `FocusState<KSVideoPlayerView.FocusableField?>.Binding`.

### `Sources/KSPlayer/SwiftUI/TVOS/TVContentTabsView.swift`
- Abas (plano item 5): `Info`, `Chapters` (condicional — só aparece se
  `player.chapters` não-vazio, como o nativo com `navigationMarkerGroups`), `Audio`
  (condicional a tracks), `Subtitles`, `Speed`, `Advanced`. Labels `.body`; painel
  com `tvPlayerControlMaterial(in: RoundedRectangle(cornerRadius: 24))`.
- **Info**: artwork + título + subtítulo + duração (do player) + sinopse + ações
  "Play from Beginning" (`seek(0)` + play) e contentMode ("Fill Screen"/"Fit to
  Screen").
- **Chapters**: lista horizontal (título + tempo, `Chapter.start`); selecionar = seek.
  Thumbnail fica para o roadmap de preview.
- **Audio/Subtitles/Speed**: listas horizontais de opções focáveis com checkmark
  (mesmos dados dos menus dos ícones — abas são o caminho explorável, menus o
  atalho, como no nativo).
- **Advanced**: video track + video type + stream type + `DynamicInfoView` + file
  size (conteúdo do `VideoSettingView` sem lugar no padrão nativo). Os `TextField`s
  de delay/busca de legenda do `VideoSettingView` **não migraram** (decisão: sem
  equivalente no player nativo; o StreamHub injeta legendas por fora).

## Arquivos editados

### `Sources/KSPlayer/SwiftUI/KSVideoPlayerView.swift`
- Branch tvOS de `controllerView`: substituído por `TVControlsOverlayView` dentro de
  um `ZStack` bottom-anchored, inserido/removido da hierarquia por
  `isMaskShow && !tvIsInitialLoading` (padrão do arquivo: entrar/sair em vez de
  opacity, preservando foco e performance), com `.transition(.opacity)` +
  `.animation(.easeInOut)` (curva padrão do sistema, plano item 9). `onAppear`/
  `onDisappear` movem o foco `.controller`/`.play` como antes. As demais plataformas
  mantêm o corpo antigo intacto (só perdeu o `#elseif os(tvOS)` de padding/gradiente).
- `overlayGradient` removido (único consumidor era o branch tvOS; o dimming agora
  vive no overlay).
- Bloco `if isDropdownShow { VideoSettingView }` do tvOS removido — as tabs vivem no
  overlay; `VideoSettingView` continua intacto para as demais plataformas.
- Estados novos (só tvOS): `tvMetadata` (+ modifier público
  `tvPlayerMetadata(_:)` — aditivo, inits públicos intocados), `tvSkipHint`,
  `tvIsInitialLoading`.
- Loading inicial (plano item 6a): `.preparing` → tela preta com `ProgressView()`
  central e controles suprimidos; flag ligada em `.preparing` e desligada em
  `.readyToPlay`/`onFinish`. `playView` fica focável durante o loading para o Back
  funcionar (dismiss direto).
- Erro (item 6c): card central mantido, com `tvPlayerControlMaterial` no tvOS
  (glass/ultraThin) e `.black.opacity(0.6)` nas demais.
- Legendas (item 7): padding inferior extra de 200pt no container do
  `VideoSubtitleView` quando `isMaskShow` (equivalente manual do
  `unobscuredContentGuide`; constante a calibrar na etapa 4).
- Gestos (item 8):
  - `onMoveCommand` ←/→ → `tvSkip(±KSOptions.tvSkipInterval)` (skip + `mask(show:)`
    + hint visual); ↑ mantém o pin; ↓ → `mask(show:true, autoHide:false)` +
    `focusableField = .info` (abre tabs).
  - `onKeyPressLeftArrow/RightArrow` usam `tvSkipInterval` no tvOS (15s preservado
    para iOS/macOS).
  - Tap/select no vídeo (tvOS) = play/pause + mostrar barra (antes: toggle da
    máscara; iOS mantém o toggle). Cobre "com vídeo pausado, select = play".
  - `onSwipe` com direção `.down` e máscara oculta abre as tabs diretamente
    (atalho nativo da pesquisa §5); demais direções seguem só mostrando a máscara.
  - `onExitCommand` formalizado: loading → dismiss; `.info` → fecha tabs e volta o
    foco à barra; máscara visível → esconde e foco no vídeo; senão → dismiss
    (tabs → controles → dismiss, um nível por vez).
- `FocusableField` passou de `fileprivate` para interno (as views novas recebem o
  `FocusState.Binding`); casos `play/controller/info` mapeiam a árvore nativa
  vídeo → transportBar → tabs.
- Abertura de tabs a partir da barra passa por callback `onOpenTabs` fechado sobre o
  `KSVideoPlayerView` (**decisão importante**: escrever
  `focusableField.wrappedValue = .info` via `FocusState.Binding` NÃO dispara o
  `willSet` que controla `isDropdownShow`; a atribuição direta à property dispara).
- `DynamicInfoView.dynamicInfo` deixou de ser `fileprivate` (a aba Advanced constrói
  a view de outro arquivo; sem mudança de API pública).

### `Sources/KSPlayer/SwiftUI/Slider.swift` (arquivo inteiro é `#if os(tvOS)`)
- Removido o tint vermelho de foco do `TVOSSlide.updateUIView` (nativo é branco;
  destaque de foco é do sistema — plano item 3).
- `TVSlide`: membros `processView`/`value`/`ranges`/`onEditingChanged` viraram
  internos (e `ranges`/`onEditingChanged` viraram `var`) para o `TVScrubberInput`
  poder reusar o motor e ressincronizar bounds; novo `onDownArrow: (() -> Void)?`
  tratado em `pressesBegan` (press ↓ na barra abre as tabs, atalho direto do
  nativo; sem handler cai no `super`).
- O fix de `.cancelled/.failed` do pan (finding 2 da auditoria) **já estava aplicado
  no working tree** (restaura `beganValue` + `onEditingChanged(false)`) — nada a
  fazer.

### `Sources/KSPlayer/AVPlayer/KSVideoPlayer.swift`
- Fix do acúmulo de swipe recognizers (finding 6): os 4 `UISwipeGestureRecognizer`
  saíram do branch `.preparing` de `player(layer:state:)` e agora são registrados em
  `makeView` via `addSwipeGestures(to:)`, com guarda de identidade
  (`weak var swipeGestureView`) — uma única vez por view, re-registrando apenas se a
  view do player mudar (troca de engine). Vale para iOS também (correção de bug,
  prevista no plano). `resetPlayer()` zera a referência.

### `Sources/KSPlayer/AVPlayer/KSOptions.swift`
- `static var tvSkipInterval = 10` (plano item 8; default nativo de ±10s).

## O que já estava pronto no working tree (não refeito)

- Finding 1 (pin da máscara sobrevive a soluço de buffer): `isMaskPinned` já existia
  no `Coordinator`.
- Finding 2 (`.cancelled/.failed` do pan): já corrigido em `Slider.swift`.
- Finding 3 (`onFinish` conectado + card de erro): já presente em
  `KSVideoPlayerView`.
- Finding 4 (spinner em `.preparing`): já corrigido no
  `KSVideoPlayerViewBuilder.titleView`.
- Obs.: o working tree contém muitas outras modificações pré-existentes fora do
  escopo desta reforma (`KSAVPlayer`, `MEPlayer/*`, `Metal/*`, `Core/*`, etc.) que
  não foram tocadas.

## Decisões onde o plano era ambíguo

1. **Tabs dentro do overlay** (e não sibling no `body`): garante "abaixo da
   transport bar" e evita `.focused` aninhados conflitantes.
2. **`TVSlide` mantido com `UIProgressView` oculto** (em vez de removê-lo): preserva
   intacto o handling de `UIPress`/pan para o uso legado (`TVOSSlide`) e novo.
3. **Spinner de rebuffer no leading da linha de tempos** — a barra nativa não tem
   botão play/pause visível para ancorar.
4. **Expiração do hint de skip via `.task(id:)`** no overlay — evita `DispatchQueue`
   capturando o view struct sob StrictConcurrency.
5. **`.buttonStyle(.glass)` não usado**: o material do chip já vem de
   `tvPlayerControlMaterial`; usar os dois duplicaria o platter.
6. **Select no vídeo = play/pause** (não toggle de máscara) — coluna "Efeito" da
   tabela do item 8; pausar já revela os controles via estado.
7. **Padding de 200pt para legendas** como aproximação da altura do overlay —
   calibrar na etapa 4 (screenshot).
8. **Aba Subtitles sempre visível** (tem "Off"); Audio/Chapters condicionais.

## Pendências (para etapa 4 / follow-ups)

- **P2 do plano**: segurar ←/→ para FF/REW contínuo 2x→3x→4x via `playbackRate`
  (exige motor de press-and-hold novo; explicitamente adiável).
- Cancelar scrub com Menu/Back restaurando a posição anterior (pesquisa §6.6): hoje
  Back durante o scrub esconde a máscara; `TVSlide` não trata `.menu`.
- Swipe ↓ (não press) com foco na transport bar não abre as tabs — vira movimento de
  foco do sistema; press ↓ cobre o caso.
- Depois de fechar as tabs com Back, a máscara permanece pinada (`mask(show: true)`
  não limpa `isMaskPinned`); só some com outro Back. Avaliar API de "unpin".
- Troca de aba é por select; o nativo troca ao focar o label — polimento de foco da
  etapa 4 (idem foco inicial preferir o scrubber em vez do primeiro chip).
- Checkmark da aba Audio pode ficar desatualizado até o próximo re-render (selecionar
  track não republica o `Coordinator`).
- Constantes visuais (track 8pt, chips 64pt, hint acima da barra, gradiente 0.35,
  padding 200pt) são aproximações — comparar lado a lado com o player nativo na
  etapa 4 e ajustar.
- Validação de compilação/execução real (tvOS/iOS/macOS) é do dono do projeto; aqui
  só houve `swiftc -parse` por plataforma.
