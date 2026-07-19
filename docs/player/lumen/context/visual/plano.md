# Plano — Reforma da UI tvOS do player (etapa 2/4)

Etapa 2/4 da evolução visual do fork. Entrada: `context/visual/pesquisa.md` (o "padrão
system" do `AVPlayerViewController` de tvOS 15/26, usado aqui como vara de medir) e
`docs/08-ui-e-views.md` (mapa do código de UI). Saída desta etapa: este plano. A etapa 3
implementa; a etapa 4 valida contra o critério definido no final deste documento.

## Objetivo

Deixar a experiência tvOS do player SwiftUI do fork (`KSVideoPlayerView` + componentes)
**visualmente e interativamente idêntica ao player nativo do Apple TV** (anatomia de
tvOS 15+, material de tvOS 26 quando disponível), sem tocar na experiência de
iOS/macOS/visionOS.

## Princípios (nesta ordem)

1. **APIs do sistema antes de redesenho manual.** Tudo que o SwiftUI/tvOS dá de graça
   entra primeiro: SF Symbols, text styles do sistema (que já carregam os tamanhos de
   tipografia tvOS da pesquisa §3), `Material` (`.ultraThinMaterial` etc.) para o
   acabamento dos controles, `.buttonStyle(.borderless)` para o efeito de foco padrão
   (glow/scale/sombra do Focus Engine, pesquisa §8 — nunca reimplementar foco na mão),
   `Menu`/`Picker` inline (tvOS 17+, já usado em `MenuView`), `ProgressView()` para
   spinner, `onPlayPauseCommand`/`onMoveCommand`/`onExitCommand` para o remote, e — em
   tvOS 26 — as APIs de Liquid Glass do SwiftUI (`glassEffect(_:in:)`,
   `GlassEffectContainer`, `.buttonStyle(.glass)`) atrás de `#available(tvOS 26, *)`,
   com fallback `.ultraThinMaterial` para tvOS 16-25 (mesmo modelo de degradação que a
   própria Apple usa em hardware antigo, pesquisa §2.2).
   As assinaturas exatas das APIs de glass devem ser conferidas no SDK na etapa 3 antes
   de usar (não confiar de memória).
2. **`AVPlayerViewController` foi considerado e descartado como base**: o caminho
   principal do StreamHub é `KSMEPlayer` (FFmpeg/Metal, MKV de debrid), que não produz
   um `AVPlayer` — logo não há como herdar a UI nativa de verdade (pesquisa, introdução:
   é exatamente a categoria "player custom" do Disney+/Infuse). A reforma replica o
   visual/interação por SwiftUI, componente a componente, usando a pesquisa como spec.
3. **Escopo SOMENTE tvOS.** Todas as mudanças vivem em arquivos novos guardados por
   `#if os(tvOS)` ou dentro dos branches `#if os(tvOS)` já existentes de
   `KSVideoPlayerView.swift`. Os branches de iOS/macOS/xrOS não são editados; o caminho
   UIKit (`Sources/KSPlayer/Video/`) não é tocado.
4. **Fidelidade medida pela pesquisa**, não por gosto: cada componente abaixo referencia
   a seção da `pesquisa.md` que define o alvo.

## Decisão de arquitetura

A UI tvOS atual está espalhada em branches `#if os(tvOS)` de `KSVideoPlayerView.swift`
(barra única inferior de `VideoControllerView`, painel `VideoSettingView` inline via
`isDropdownShow`, `Slider`/`TVSlide`). O plano extrai a experiência tvOS para um
subdiretório dedicado:

```
Sources/KSPlayer/SwiftUI/TVOS/          (todos os arquivos com #if os(tvOS) ... #endif)
├── TVControlsOverlayView.swift         overlay completo: title view + ícones + transport bar + dimming
├── TVTransportBar.swift                scrubber novo + labels de tempo + spinner de buffering
├── TVContentTabsView.swift             abas Info / Capítulos / Áudio / Legendas / Velocidade / Avançado
└── TVGlassMaterial.swift               helper de material (glassEffect tvOS 26 / ultraThinMaterial fallback)
```

`KSVideoPlayerView` continua sendo o entry point público (nenhuma mudança de API para o
StreamHub); seus branches tvOS passam a compor essas views novas. `VideoControllerView`,
`VideoTimeShowView` e `VideoSettingView` continuam existindo intactos para as demais
plataformas — apenas deixam de ser usados no tvOS.

---

## Inventário componente a componente

### 1. `KSVideoPlayerView` (raiz) — REFORMAR

- **Hoje**: ZStack com `playView` + legendas + `controllerView` + `VideoSettingView`
  inline; máquina de foco `FocusableField` (`play`/`controller`/`info`);
  `onMoveCommand`/`onExitCommand`/`onPlayPauseCommand` (`SwiftUI/KSVideoPlayerView.swift:63-124,225-241`).
- **Alvo** (pesquisa §1, §5): mesma estrutura, mas os branches tvOS compõem
  `TVControlsOverlayView` e `TVContentTabsView`; máquina de foco reformulada para
  espelhar a árvore de interação nativa: `video` (tela cheia, gestos agem no conteúdo) →
  `transportBar` (controles visíveis, foco nos botões/scrubber) → `tabs` (painel
  aberto). Back/Menu desce um nível por vez até o dismiss — o `onExitCommand` atual já
  faz isso em espírito; formalizar.
- **Arquivos**: editar `SwiftUI/KSVideoPlayerView.swift` (somente branches
  `#if os(tvOS)`); criar `SwiftUI/TVOS/TVControlsOverlayView.swift`.

### 2. `VideoControllerView` (branch tvOS: linha única título+botões) — SUBSTITUIR

- **Hoje**: uma linha inferior com título à esquerda e 8 botões `*.circle.fill` em
  `.font(.title3)` à direita (`SwiftUI/KSVideoPlayerView.swift:398-434`). Não existe no
  player nativo: lá não há fileira de botões circulares.
- **Alvo** (pesquisa §1.1, §1.2): `TVControlsOverlayView` com a anatomia nativa:
  - **Title view** acima da transport bar, alinhada à esquerda: título (text style
    `.headline`) + subtítulo/metadata secundária opcional (o StreamHub injeta via
    `title`; prever um campo `subtitle` opcional novo). Suprimível.
  - **Ícones do sistema** na linha da title view, alinhados à direita (trailing da
    transport bar, como `transportBarCustomMenuItems`): legendas (`Menu` de seleção),
    áudio (`Menu`), velocidade (`Menu`, análogo ao `player.speeds` nativo), PiP.
    Ícones SF Symbols "chapados" (sem variante `.circle.fill` — o fundo circular vem do
    material/glass do container, não do glifo). Mute/contentMode saem da barra
    (não existem no player nativo; contentMode migra para a aba Info como ação, mute
    não tem equivalente de remote e sai do tvOS).
  - **Transport bar** full-width abaixo (item 3).
  - Sem botão de fechar/dismiss (nativo não tem; Back cumpre o papel).
- **Arquivos**: criar `SwiftUI/TVOS/TVControlsOverlayView.swift`; editar
  `SwiftUI/KSVideoPlayerView.swift` (branch tvOS de `controllerView`); ajustes de
  fábrica em `SwiftUI/KSVideoPlayerViewBuilder.swift` só se guardados por `os(tvOS)`.

### 3. `VideoTimeShowView` + `Slider`/`TVOSSlide`/`TVSlide` — REFORMAR (visual) + MANTER (motor de input)

- **Hoje**: `HStack` tempo-corrente / slider / tempo-total (`SwiftUI/KSVideoPlayerView.swift:586-618`);
  `TVSlide` é um `UIControl` com `UIProgressView` + press left/right acelerado + pan
  (`SwiftUI/Slider.swift:60-170`), tint vermelho quando focado.
- **Alvo** (pesquisa §1.2, §5, §6): visual do scrubber nativo — track fina translúcida,
  porção reproduzida em branco sólido, playhead visível quando em scrub; **tempo
  decorrido à esquerda e tempo restante ("−h:mm:ss") à direita, abaixo da barra**, em
  monospaced digits (text style `.caption1`-equivalente); durante o scrub, timestamp
  acompanha o playhead. Nota: a posição exata dos labels é detalhe observacional (não
  documentado pela Apple) — afinar por screenshot na etapa 4.
  Modelo de interação nativo: com vídeo **pausado**, swipe lateral faz scrub pelo vídeo
  inteiro; com vídeo tocando, press lateral pula (item 8). O motor de `TVSlide`
  (presses acelerados, pan, commit em select) é mantido e recebe:
  - correção dos estados `.cancelled`/`.failed` do pan (hoje deixam o player pausado
    sem seek — `context/review/ui-tvos.md` finding 2);
  - visual novo desenhado em SwiftUI por cima (o `UIProgressView` interno vira
    implementação de detalhe ou é substituído por camadas SwiftUI — decidir na etapa 3
    pelo que preservar melhor o handling de `UIPress`);
  - remoção do tint vermelho de foco (nativo é branco; destaque de foco vem do sistema);
  - **âncora/slot para o popup de thumbnail de scrub** (imagem + timestamp acima do
    playhead) — a geração da imagem é o roadmap
    `context/roadmap/progressbar-preview.md` e NÃO faz parte desta reforma; aqui só
    nasce o ponto de encaixe visual.
- **Arquivos**: editar `SwiftUI/Slider.swift`; criar `SwiftUI/TVOS/TVTransportBar.swift`;
  `VideoTimeShowView` fica intocada (segue servindo iOS/macOS/xrOS) — o branch tvOS de
  `controllerView` troca ela pela `TVTransportBar`.

### 4. Gradiente/material do overlay — REFORMAR

- **Hoje**: `overlayGradient` linear preto 0→0.7 no rodapé (`SwiftUI/KSVideoPlayerView.swift:293-300`).
- **Alvo** (pesquisa §2): duas camadas como no nativo — (a) **dimming** escuro suave na
  base (~35% de opacidade, recomendação HIG para conteúdo claro sob glass) cobrindo a
  região dos controles; (b) **material** nos elementos de controle: em tvOS 26,
  `glassEffect`/`.buttonStyle(.glass)` (variant clear — controles sobre mídia); em
  tvOS < 26, `.ultraThinMaterial`/`.thinMaterial` nos chips dos ícones e na title view.
  Centralizar em `TVGlassMaterial.swift` (um modifier `tvPlayerControlMaterial()`), para
  o fallback ficar num lugar só.
- **Arquivos**: criar `SwiftUI/TVOS/TVGlassMaterial.swift`; usar em
  `TVControlsOverlayView`/`TVTransportBar`/`TVContentTabsView`.

### 5. `VideoSettingView` inline via `isDropdownShow` — SUBSTITUIR (no tvOS)

- **Hoje**: seta ↓ foca `.info` e injeta `VideoSettingView` (ScrollView de pickers,
  campos de texto e info técnica) por cima do vídeo (`SwiftUI/KSVideoPlayerView.swift:78-83`,
  `:697-749`). Visual de formulário, nada a ver com o nativo.
- **Alvo** (pesquisa §1.3): **content tabs** abaixo da transport bar, reveladas por
  swipe/press ↓ com os controles visíveis (ou direto do estado de reprodução, como no
  nativo): abas `Info`, `Capítulos` (condicional — `MediaPlayerProtocol.chapters` já
  entrega capítulos do FFmpeg em `MEPlayer/MEPlayerItem.swift:253-263`; aba só aparece
  se não-vazio, como o nativo faz com `navigationMarkerGroups`), `Áudio`, `Legendas`,
  `Velocidade`, `Avançado`:
  - **Info**: artwork/título/descrição (campos opcionais injetáveis pelo app — análogo a
    `externalMetadata`) + ações (ex.: "Reproduzir do início", contentMode); duração vem
    do player.
  - **Capítulos**: lista horizontal de capítulos (título + tempo; thumbnail fica para o
    roadmap de preview); selecionar = seek.
  - **Áudio/Legendas/Velocidade**: as seleções que hoje vivem em `MenuView`/pickers —
    listas horizontais de opções focáveis com check, estilo tabs nativas. (Os mesmos
    dados também ficam acessíveis pelos menus dos ícones da transport bar; as abas são o
    caminho "explorável", os menus o atalho — como no nativo, onde legendas/áudio têm
    ícone E aparecem em tabs.)
  - **Avançado**: `DynamicInfoView` + file size + track de vídeo (conteúdo do
    `VideoSettingView` atual que não tem lugar no padrão nativo, preservado numa aba
    custom — equivalente a `customInfoViewControllers`).
  - `Up Next` fica **fora** desta reforma (depende de dados de catálogo do StreamHub;
    a estrutura de abas deve aceitar abas injetadas pelo app no futuro).
- **Arquivos**: criar `SwiftUI/TVOS/TVContentTabsView.swift`; editar
  `SwiftUI/KSVideoPlayerView.swift` (branch tvOS: `isDropdownShow` passa a apresentar as
  tabs; `VideoSettingView` deixa de ser usada no tvOS, permanece nas demais).

### 6. Estados de loading/buffering/erro — REFORMAR

- **Hoje**: spinner ao lado do título quando `.buffering || .preparing`; card de erro
  central preto 0.6 (`SwiftUI/KSVideoPlayerView.swift:85-97,404-405`).
- **Alvo** (pesquisa §7): (a) **carregamento inicial** (`.preparing`, antes do primeiro
  frame): tela preta com `ProgressView()` centralizado, sem controles — padrão HIG para
  loading > 2s; (b) **rebuffering em reprodução**: spinner pequeno junto ao play/pause
  na transport bar (não centralizado); (c) **erro**: manter o card central (o nativo não
  tem equivalente público; é ganho do fork), reestilizado com o material do item 4.
- **Arquivos**: `TVControlsOverlayView.swift`/`TVTransportBar.swift` + branch tvOS de
  `KSVideoPlayerView.swift`.

### 7. Legendas sobem com os controles — REFORMAR (pequeno)

- **Hoje**: `VideoSubtitleView` centralizada, ignora a presença da barra — legendas
  ficam por baixo dos controles quando a máscara aparece.
- **Alvo** (pesquisa §4, `unobscuredContentGuide`): quando `isMaskShow == true` no tvOS,
  aplicar padding inferior extra à área de legenda igual à altura do overlay de
  controles (equivalente manual do guide nativo). Estilo/render das legendas em si está
  fora de escopo (roadmap `use-system-caption-appearance.md`).
- **Arquivos**: branch tvOS em `SwiftUI/KSVideoPlayerView.swift` (posicionamento do
  `VideoSubtitleView`).

### 8. Gestos do Siri Remote — REFORMAR

- **Hoje**: ←/→ = skip ±15s; ↑ = pin da máscara; ↓ = painel info; select em `.play` sem
  função dedicada; play/pause ok; swipe genérico mostra máscara
  (`SwiftUI/KSVideoPlayerView.swift:225-241`, `AVPlayer/KSVideoPlayer.swift:229-267`).
- **Alvo** (pesquisa §5, tabela): paridade com a coluna "Efeito":
  | Gesto | Efeito alvo |
  |---|---|
  | Toque na superfície (swipe leve) | mostra controles sem pausar (já ok via `onSwipe`) |
  | Press central / play-pause | play/pause (ok); com vídeo pausado e controles visíveis, select no vídeo = play |
  | Press ←/→ (tocando) | **±10s** (nativo; hoje 15s) com feedback visual: transport bar aparece brevemente com glifo de skip — hoje não há feedback nenhum quando escondida (`context/review/ui-tvos.md` finding 5). Intervalo vira `KSOptions.tvSkipInterval` (default 10) |
  | Segurar ←/→ | avanço/retrocesso contínuo 2x→3x→4x via `playbackRate` — **P2** (fase 5; único item da tabela que exige motor novo) |
  | Swipe lateral **pausado** | scrub pelo vídeo (motor `TVSlide` existente, item 3) |
  | Swipe/press ↓ | abre content tabs (item 5) |
  | Swipe ↑ | sem função própria (no nativo abre `customOverlayViewController`, que não temos); manter o pin atual como comportamento de conveniência |
  | Menu/Back | fecha um nível por vez: tabs → controles → dismiss (ok, formalizar) |
- Correção associada no `Coordinator`: acúmulo infinito de swipe recognizers a cada
  `.preparing` (`AVPlayer/KSVideoPlayer.swift:250-265`, finding 6 da auditoria) —
  registrar uma única vez em `makeView`.
- **Arquivos**: `SwiftUI/KSVideoPlayerView.swift` (branch tvOS),
  `AVPlayer/KSVideoPlayer.swift` (fix pontual, vale para iOS também — é correção de
  bug, não mudança de UX de outra plataforma), `AVPlayer/KSOptions.swift`
  (`tvSkipInterval`).

### 9. Tipografia, layout e timing — REFORMAR (transversal)

- **Alvo** (pesquisa §3, §4, §9): usar text styles do sistema em tudo (nunca tamanho
  absoluto): título `.headline`, tempos `.caption`/`.caption2` + `.monospacedDigit()`,
  labels de tabs `.body`. Margens: 80pt laterais / 60pt base (safe area tvOS; hoje há
  80/80 — ajustar base). Auto-hide: manter 5s (`KSOptions.animateDelayTimeInterval` já
  alinhado ao nativo, pesquisa §9). Animações de mostrar/esconder overlay: fade+slide
  sutil com curva padrão do sistema (`.easeInOut` default), sem inventar timing.
- **Arquivos**: todos os novos + branches tvOS.

### 10. O que NÃO entra nesta reforma (fronteiras explícitas)

- Geração de thumbnails de scrub (roadmap `progressbar-preview.md`) — só o slot visual.
- Estilo de legenda do sistema (roadmap `use-system-caption-appearance.md`).
- Aba Up Next / `AVContentProposal`-like (depende do catálogo StreamHub; abas ficam
  extensíveis).
- Siri "What did she say?" e afins — exclusivos de `AVPlayerViewController`, sem API
  pública para player custom (pesquisa §5).
- Caminho UIKit (`Sources/KSPlayer/Video/`) — permanece como está.

---

## Ordem de execução (etapa 3)

Cada fase compila e roda de forma independente; a UI tvOS nunca fica quebrada entre
fases.

1. **Fase 0 — Fundação e fixes de base**
   Criar `SwiftUI/TVOS/` com `TVGlassMaterial.swift`; corrigir `TVSlide`
   `.cancelled/.failed` (`Slider.swift`) e o acúmulo de swipe recognizers
   (`KSVideoPlayer.swift`); adicionar `KSOptions.tvSkipInterval`. Zero mudança visual.
2. **Fase 1 — Transport bar + title view**
   `TVTransportBar.swift` + `TVControlsOverlayView.swift`; trocar o branch tvOS de
   `controllerView` em `KSVideoPlayerView.swift` para o overlay novo (title view +
   ícones à direita + scrubber + tempos + dimming/material). Itens 2, 3, 4, 9.
3. **Fase 2 — Interação do remote**
   Skip ±10s com feedback visual, select=play quando pausado, pausado+swipe→scrub
   integrado ao visual novo, hierarquia de Back formalizada. Item 8 (menos o P2).
4. **Fase 3 — Content tabs**
   `TVContentTabsView.swift` (Info/Capítulos/Áudio/Legendas/Velocidade/Avançado);
   remover `VideoSettingView` do fluxo tvOS. Item 5.
5. **Fase 4 — Estados e legibilidade**
   Loading inicial centralizado, spinner de rebuffer junto ao play/pause, card de erro
   reestilizado, legendas subindo com a máscara. Itens 6, 7.
6. **Fase 5 — Polimento e P2**
   Liquid Glass tvOS 26 (`glassEffect` atrás de `#available`), ajustes finos de
   animação/espaçamento contra screenshots reais, segurar ←/→ para FF/REW 2x-4x (se o
   custo couber), varredura final de `#if os(tvOS)` para garantir isolamento.

---

## Critério de validação da etapa 4

A etapa 4 aprova a reforma quando TODOS os itens abaixo passarem:

1. **Checklist de paridade com a pesquisa** — tabela item a item cobrindo: anatomia
   (§1.1-§1.4: title view, transport bar com ícones à direita, content tabs, estados),
   materiais (§2: dimming + material/glass com fallback), tipografia (§3: só text
   styles do sistema, digits monoespaçados), layout (§4: margens 80/60, overlay não
   cobre legenda), gestos (§5: tabela completa, exceto P2 explícitos), buffering (§7:
   inicial centralizado / rebuffer na barra), foco (§8: efeitos de foco 100% do
   sistema, nenhum scale/sombra manual em botão), timing (§9: auto-hide 5s). Cada linha
   com evidência `arquivo:linha`.
2. **Comparação visual lado a lado** — screenshots do fork (simulador/Apple TV,
   capturados pelo dono do projeto — builds e capturas são dele, conforme fluxo de
   trabalho deste repo) contra o player nativo (app TV do tvOS 26) nas cenas: reprodução
   com controles ocultos, controles visíveis, pausado em scrub, tabs abertas,
   buffering, erro. Critério: mesma anatomia e hierarquia visual; divergências
   registradas e ou aceitas explicitamente (ex.: glass real só em hardware suportado) ou
   viram follow-up.
3. **Roteiro de gestos no dispositivo** — executar a tabela do item 8 gesto a gesto no
   Siri Remote (ou simulador) e confirmar cada "Efeito alvo", incluindo os regressivos:
   pin de controles sobrevive a soluço de buffer, pan cancelado não deixa o player
   pausado, skip com barra oculta dá feedback.
4. **Não-regressão de plataforma** — o diff da etapa 3 só toca: arquivos novos em
   `SwiftUI/TVOS/`, branches `#if os(tvOS)` de arquivos existentes, e os dois fixes de
   `KSVideoPlayer.swift`/`Slider.swift` (verificável por inspeção do diff); o pacote
   compila para iOS, macOS e tvOS (validação de build pelo dono) sem warnings novos; a
   UI de iOS/macOS não muda (screenshot rápido de sanidade).
5. **API pública preservada** — `KSVideoPlayerView.init(...)` e o contrato do
   `Coordinator` inalterados (o StreamHub não precisa mudar para adotar a reforma);
   aditivos novos (subtitle da title view, metadata da aba Info, `tvSkipInterval`)
   são opcionais com default.
