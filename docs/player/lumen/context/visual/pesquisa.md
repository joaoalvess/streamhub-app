# Pesquisa — UI nativa de player de vídeo do tvOS (`AVPlayerViewController`)

Etapa 1/4 da evolução visual do fork. Escopo: documentar, com o máximo de precisão
possível a partir de documentação oficial da Apple (HIG, referência de API do AVKit,
sessões WWDC) e de cobertura de imprensa técnica, exatamente o que `AVPlayerViewController`
entrega de graça no tvOS moderno — sem inventar nada, sem propor nada próprio. As
próximas etapas (2-4) é que vão decidir o que replicar dentro do player SwiftUI custom
do fork (`KSVideoPlayerView`). Este documento é só o retrato do "padrão system" que serve
de vara de medir.

Duas eras importam aqui, porque as duas ainda estão em produção e a segunda é uma casca
visual em cima da primeira, não uma reescrita:

- **tvOS 15 (2021)** — redesenho estrutural do player: layout com title view + transport
  bar + content tabs (Info/Chapters/Up Next) substituindo o painel único de swipe-down
  de tvOS ≤14. Este é o modelo de **interação** vigente até hoje.
- **tvOS 26 (lançado publicamente em setembro/2025, é o que roda em produção em
  2026)** — redesenho de **material**: a mesma estrutura de tvOS 15 (title view,
  transport bar, tabs, contextual actions) ganha a pele "Liquid Glass" (vidro
  translúcido com reflexo/refração em tempo real), mas a árvore de interação e os
  gestos do Siri Remote não mudaram. Liquid Glass só renderiza em Apple TV 4K de 2ª e
  3ª geração (hardware mais antigo continua com o material opaco de tvOS 15-25).

Importante para o dono do projeto: **apps com player custom (não baseado em
`AVPlayerViewController`) não recebem nada disto de graça** — nem o material Liquid
Glass, nem os ícones/tabs, nem scrubbing com preview, nem PiP, nem "dialogue boost".
A cobertura de tvOS 26 confirma isso citando o Disney+ como exemplo de app com player
próprio que continua sem Liquid Glass e sem vários dos recursos do player do sistema
mesmo na versão atual do tvOS — ou seja, esta é exatamente a categoria em que o
KSPlayer/StreamHub está hoje.

---

## 1. Anatomia da UI (estrutura, tvOS 15+)

### 1.1 Title view

Faixa acima da transport bar, mostrando o que está sendo reproduzido assim que a
reprodução começa. Alimentada por metadados do `AVPlayerItem`:

| Campo | Identificador `AVMetadataIdentifier` |
|---|---|
| Título | `commonIdentifierTitle` |
| Subtítulo | `iTunesMetadataTrackSubTitle` |
| Artwork | `commonIdentifierArtwork` |
| Descrição | `commonIdentifierDescription` |
| Gênero | `quickTimeMetadataGenre` |
| Classificação indicativa | `iTunesMetadataContentRating` |

Se o `AVAsset` já tiver metadados embutidos eles são usados automaticamente; senão, o
app popula via `AVPlayerItem.externalMetadata`. Para conteúdo ao vivo, a title view pode
mostrar um badge de estado. É suprimível via
`playerViewController.transportBarIncludesTitleView = false`.

### 1.2 Transport bar (barra de transporte)

Fica sobre o scrubber, na parte inferior. Controles padrão do sistema, sempre presentes:
legendas/closed captions, seleção de idioma de áudio, Picture in Picture. A partir de
tvOS 15 esses controles viraram **ícones dedicados na própria transport bar** — antes
(tvOS ≤14) essas opções ficavam escondidas atrás do gesto de swipe down.

Customização pública (`transportBarCustomMenuItems: [UIMenuElement]`): controles extras
alinhados à borda final (trailing) da barra, aceitando `UIAction` e `UIMenu` (até 1
nível de aninhamento com `.displayInline`):

```swift
let favoriteAction = UIAction(title: "Favorites", image: UIImage(systemName: "heart")) { _ in }
let submenu = UIMenu(title: "Speed", options: [.displayInline, .singleSelection], children: [...])
let menu = UIMenu(image: UIImage(systemName: "gearshape"), children: [submenu])
playerViewController.transportBarCustomMenuItems = [favoriteAction, menu]
```

Desde tvOS 16 (WWDC22), o próprio sistema oferece um seletor de velocidade nativo via
`player.speeds: [AVPlaybackSpeed]` — populando esse array o sistema desenha o menu de
velocidades na transport bar sem UI própria:

```swift
let newSpeed = AVPlaybackSpeed(rate: 2.5, localizedName: "Two and a half times speed")
player.speeds.append(newSpeed)
```

### 1.3 Content tabs — Info / Chapters / Up Next (tvOS 15+)

Aparecem abaixo da transport bar quando o viewer navega para baixo. Não são mais um
painel único (era assim em tvOS ≤14) — são abas:

- **Info** — aparece automaticamente se há metadados embutidos ou `externalMetadata`.
  Mostra artwork, título, duração (vem do próprio asset), classificação indicativa e
  descrição. Aceita até **2 ações extras** na borda final via
  `infoViewActions: [UIAction]!` (o sistema já injeta por padrão uma ação de "reproduzir
  do início"; ex. de uso: adicionar "Watch Later").
- **Chapters** — aparece automaticamente quando `AVPlayerItem.navigationMarkerGroups` é
  fornecido; cada marcador tem título e, geralmente, uma imagem thumbnail do próprio
  vídeo. Selecionar um capítulo salta para aquele ponto.
- **Up Next** — populada a partir de `AVPlayerItem.nextContentProposal`
  (`AVContentProposal`), objeto com `title`, `previewImage`, `contentTimeForTransition`
  (quando no timeline do item atual a proposta deve aparecer) e
  `automaticAcceptanceInterval` (quanto tempo depois do fim da reprodução a próxima
  proposta é aceita automaticamente — é o autoplay/countdown do próximo episódio).
  Delegate: `playerViewController(_:shouldPresent:)`,
  `playerViewController(_:didAccept:)`, `playerViewController(_:didReject:)`.
- **Abas customizadas** — `customInfoViewControllers: [UIViewController]` (substituiu o
  antigo `customInfoViewController`, singular, deprecado em tvOS 15). Cada
  `UIViewController` vira uma aba; o `.title` do controller vira o título da aba; é
  obrigatório setar `preferredContentSize` (ou constraints) porque o sistema
  redimensiona **todas** as abas para a altura da mais alta.

### 1.4 Contextual actions (ex.: "Skip Intro")

`contextualActions: [UIAction]` — controles que aparecem só durante uma janela de tempo
específica da reprodução (ex.: botão "Pular introdução" só nos primeiros 90s). Não há
timing automático: o app observa o tempo (`addPeriodicTimeObserver`/
`addBoundaryTimeObserver`) e atribui/zera o array conforme o playhead entra/sai do
intervalo:

```swift
timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 1), queue: .main) { time in
    playerViewController.contextualActions = skipRange.containsTime(time) ? [skipAction] : []
}
```

### 1.5 Overlays customizados (modelo pré-tvOS 15, ainda válido)

- `customOverlayViewController: UIViewController?` — conteúdo totalmente interativo,
  normalmente oculto, revelado por swipe up, com dica visual ("deslize para mais") na
  parte inferior da tela; AVKit cuida sozinho de animação de entrada/saída e do dismiss
  (swipe down ou botão Menu).
- `contentOverlayView: UIView?` — camada não-interativa (ex.: logotipo de canal),
  coexiste com o overlay customizado, sem gerenciamento de dismissal.
- Boa prática explícita da Apple (WWDC19): **não instalar gesture recognizers próprios**
  para swipe up — usar `customOverlayViewController`, que já vem com o ciclo de vida de
  `UIViewController` padrão.

---

## 2. Materiais visuais

### 2.1 Antes de tvOS 26 — `UIBlurEffect`/materiais "standard"

Overlays do player usam os materiais padrão do sistema (`UIBlurEffect`,
`UIVibrancyEffect`, `UIVisualEffectView`). Para a camada de conteúdo (o que se aplicaria
a um overlay de player), a HIG recomenda por caso de uso:

| Material | Opacidade relativa | Uso recomendado em tvOS |
|---|---|---|
| `ultraThin` | mais translúcido | telas full-screen que precisem de esquema de cor claro |
| `thin` | translúcido | overlays que obscurecem parcialmente o conteúdo, esquema claro |
| `regular` | padrão | overlays que obscurecem parcialmente o conteúdo |
| `thick` | mais opaco | overlays que precisem de esquema de cor escuro |

Vibrancy para labels sobre esses materiais segue os níveis padrão `label` /
`secondaryLabel` / `tertiaryLabel` / `quaternaryLabel` (este último não recomendado
sobre `thin`/`ultraThin` por baixo contraste).

### 2.2 tvOS 26 — Liquid Glass

Substitui o material acima na camada de controles/navegação (não na camada de
conteúdo). Dois variantes:

- **Regular** — borra e ajusta luminosidade do conteúdo atrás, com scroll-edge effect
  para reforçar legibilidade; indicado quando o fundo pode prejudicar leitura (a maioria
  dos controles com texto).
- **Clear** — altamente translúcido, prioriza ver o conteúdo por trás; indicado para
  controles flutuando sobre mídia (foto/vídeo) — **é este o variant usado na transport
  bar do player de vídeo**. A HIG recomenda, se o conteúdo atrás for muito claro,
  adicionar uma camada de "dimming" escura a ~35% de opacidade por baixo do glass para
  não perder contraste — mas a cobertura de tvOS 26 na imprensa (ver Referências) indica
  que a Apple não aplicou esse dimming de forma agressiva na scrub bar do próprio player
  de vídeo: há relato explícito de usuário de que "a scrub bar tem muito menos contraste
  agora" comparado a tvOS 25.

No player, concretamente: a barra de progresso e os botões ao redor (play/pause,
skip, legendas, PiP) ficam com acabamento de vidro; os botões refletem o que passa por
trás na scrub bar — ficam mais claros quando o texto branco do timestamp passa por
baixo deles durante a reprodução (efeito dinâmico em tempo real, não só um blur
estático).

**Requisito de hardware**: Liquid Glass no player só renderiza em Apple TV 4K de 2ª e 3ª
geração; hardware mais antigo recebe o material opaco padrão de tvOS 15-25. **Adoção**:
segue o mesmo modelo de tvOS 15 — apps que usam `AVPlayerViewController` ganham o novo
material automaticamente ao serem recompilados contra o SDK de tvOS 26, sem mudança de
código; apps com player custom continuam com sua própria aparência.

---

## 3. Tipografia

Fonte do sistema: **San Francisco (SF Pro)**; tvOS também expõe a serifada **New York**
como opção de estilo de texto. Por causa da distância de visualização (~3 m/10 pés), os
tamanhos-base do tvOS são muito maiores que os de iOS:

| Estilo | Peso | Tamanho (pt) | Leading (pt) | Peso "emphasized" |
|---|---|---|---|---|
| Title 1 | Medium | 76 | 96 | Bold |
| Title 2 | Medium | 57 | 66 | Bold |
| Title 3 | Medium | 48 | 56 | Bold |
| Headline | Medium | 38 | 46 | Bold |
| Subtitle 1 | Regular | 38 | 46 | Medium |
| Callout | Medium | 31 | 38 | Bold |
| Body | Medium | 29 | 36 | Bold |
| Caption 1 | Medium | 25 | 32 | Bold |
| Caption 2 | Medium | 23 | 30 | Bold |

Tamanho de texto padrão do sistema (`.body`) é **29pt**, mínimo recomendado **23pt**
(contra 17pt/11pt em iOS) — pontos calculados a **72 ppi @1x / 144 ppi @2x**. Regra
prática da HIG: evitar pesos "Light"; preferir Regular/Medium/Semibold/Bold para manter
legibilidade a distância.

---

## 4. Layout e dimensões

- **Safe area do tvOS**: 60pt do topo e da base, 80pt das laterais — é a margem mínima
  recomendada pela própria Apple para qualquer conteúdo primário, para tolerar overscan
  de TVs mais antigas.
- **`unobscuredContentGuide: UILayoutGuide`** (read-only, tvOS 11+) — guide de layout que
  representa a área da tela que os controles de reprodução (quando visíveis) **não**
  cobrem; existe especificamente para o app poder posicionar overlays próprios sem que
  fiquem escondidos atrás da transport bar/tabs quando elas aparecem.
- tvOS **não adapta layout por tamanho de tela** como iOS/iPadOS — a mesma interface é
  desenhada para renderizar igual em qualquer TV; não há breakpoints de size class.

---

## 5. Gestos do Siri Remote

Existem duas gerações de remote com nomenclatura de gesto ligeiramente diferente, mas
comportamento equivalente. 1ª geração (2015): superfície de toque retangular inteira.
2ª geração (2021+): "clickpad" com anel físico clicável nas quatro direções, que também
aceita gestos de deslizar e — novidade exclusiva desta geração — **fazer círculos com o
dedo no próprio anel** para um controle mais fino de scrub.

| Gesto | 1ª geração | 2ª geração | Efeito |
|---|---|---|---|
| Toque simples na superfície | encostar o dedo | segurar o dedo no clickpad | revela dica visual / mostra controles sem pausar |
| Press central | pressionar Play/Pause físico ou tocar a superfície | pressionar o centro do clickpad | play/pause |
| Click/press lateral (esquerda/direita) | tocar e pressionar | pressionar o anel esquerda/direita | pula ±10s; pressionar de novo pula mais ±10s |
| Segurar lateral | segurar pressionado | segurar pressionado no anel | avanço/retrocesso contínuo; pressionar repetidamente cicla velocidade 2x→3x→4x |
| Swipe lateral (com o vídeo **pausado**) | deslizar na superfície | deslizar no anel | scrub rápido pelo vídeo inteiro; thumbnail aparece na timeline (ver §6) |
| Círculo no anel (só 2ª geração, pausado) | — | traçar círculo com o dedo | scrub de alta precisão (mais fino que o swipe linear) |
| Swipe down / press down no anel | mostrar controles, depois deslizar para baixo | pressionar para baixo no anel (atalho direto) ou deslizar para baixo | abre as abas Info + Up Next (+ Chapters, se houver) |
| Swipe up | deslizar para cima | deslizar para cima | abre `customOverlayViewController`, se o app tiver definido um |
| Menu/Back | pressionar Menu | pressionar Back | fecha overlay/painel aberto; se nada aberto, sai do player (dismiss) |
| Toque lateral (posicional) | tocar canto esquerdo/direito/cima/baixo sem pressionar | idem | uso opcional para navegação (ex.: EPG em apps de TV ao vivo); a HIG recomenda não responder a isso durante reprodução ao vivo para evitar toques acidentais |

Pontos importantes documentados explicitamente na HIG:

- **Press vs. tap**: press é a ação intencional de ativar/confirmar; tap serve para
  navegação, mas deve ser evitado como gatilho durante reprodução de vídeo ao vivo
  (toques acidentais ao segurar o remote).
- **Nunca redefinir o comportamento padrão dos gestões básicos** (swipe/press/tap) —
  são as únicas três formas de entrada que a HIG define para tvOS, e o usuário já vem
  com expectativa fixa do que cada um faz num player.
- Em telas full-screen (que é o caso do player), a recomendação da Apple é deixar os
  gestos agirem sobre o **conteúdo** (scrub, skip, etc.), não sobre navegação de foco —
  porque nesse contexto não há item visualmente "focado" para mover.
- **Mudança de comportamento tvOS 15 vs. anterior**: em tvOS ≤14, swipe down abria um
  único painel com 3 seções (info, config. de áudio/legenda, seção customizável extra).
  A partir de tvOS 15 esse painel de swipe down **deixou de existir nesse formato**:
  legendas/áudio viraram ícones fixos na própria transport bar, e o swipe down passou a
  abrir as content tabs (Info/Up Next/Chapters) descritas em §1.3.
- Siri integrada: comandos de voz nativos como "What did she say?" (repete os últimos
  segundos com legenda temporária) e "Go back to the beginning" funcionam sem código
  adicional, desde que o app use `AVPlayerViewController`.

---

## 6. Scrubbing com preview (thumbnail)

O comportamento é **automático e gratuito, mas condicional ao formato do stream**:

1. Usuário pausa o vídeo.
2. Se o conteúdo é **HLS com uma I-frame playlist** (`EXT-X-I-FRAME-STREAM-INF` na
   master playlist — o que a HLS Authoring Specification da Apple chama de "Trick Play
   track"), ao começar a deslizar lateralmente aparece uma **miniatura da imagem** do
   ponto para onde o usuário está arrastando, acima/próxima da timeline.
3. Sem I-frame playlist (arquivo local direto, progressive download, ou HLS sem trick
   play track) — **não há thumbnail nenhum**: a timeline mostra só a barra de progresso
   e o tempo (decorrido/restante), sem preview de imagem. Isso não é uma limitação de
   API pública, é a própria Apple confirmando que o recurso depende do stream fornecer
   frames de referência prontos.
4. Recomendação da própria HLS Authoring Spec: a resolução da I-frame track deveria ser
   pequena — **~145px de largura** é o valor citado como referência prática para o
   trick-play track, e o data rate escalado da I-frame variant deveria ficar igual ou
   abaixo do data rate da variant normal de mesma resolução (senão o trick play cai de
   qualidade visualmente pior que deveria).
5. "Fine precision scrubbing" (desde tvOS 12.3): ao segurar e deslizar, a velocidade de
   avanço no tempo desacelera perto do ponto exato, facilitando acertar um momento
   específico — nativo, sem código do desenvolvedor.
6. Cancelar o scrub: pressionar Menu/Back durante o arrasto descarta e volta para a
   posição anterior; confirmar é soltar/pressionar no ponto desejado.
7. Delegate relevante: `playerViewController(_:timeToSeekAfterUserNavigatedFrom:to:)` —
   deixa o app decidir se e para onde de fato dar seek quando o usuário navega (ex.:
   arredondar para o keyframe/capítulo mais próximo); e
   `playerViewController(_:willResumePlaybackAfterUserNavigatedFrom:to:)`, chamado
   quando a reprodução está prestes a retomar depois da navegação.

**Nota direta para o fork**: como o StreamHub reproduz majoritariamente streams
remotos de debrid via FFmpeg puro (MKV/HEVC, não HLS com trick play track), o
comportamento "de graça" da Apple aqui **não se aplica automaticamente** — é exatamente
o gap que o roadmap `context/roadmap/progressbar-preview.md` (já existente neste
repositório) trata como implementação própria via `AVAssetImageGenerator`/FFmpeg. Este
documento só confirma o alvo visual (thumbnail pequeno, ~145px, aparecendo só com o
vídeo pausado e arrastando), não a implementação.

---

## 7. Indicador de buffering

Este é o item **menos documentado publicamente** pela Apple — nenhuma sessão WWDC nem
página de HIG/API entra em especificação visual (cor exata, tamanho em pt, posição em
pixels) do indicador de carregamento do player nativo; ele é renderizado internamente
pelo AVKit, sem API pública de customização. O que está confirmado por observação/relatos
de desenvolvedores (não por documentação oficial — registrado aqui como tal):

- Existe um indicador de atividade nativo posicionado próximo ao botão de play/pause na
  transport bar (não centralizado na tela) enquanto o `AVPlayerItem` está em buffering.
- Não há delegate/notificação pública para "buffering começou/terminou" no
  `AVPlayerViewController` — apps que querem reagir a isso observam o próprio `AVPlayer`/
  `AVPlayerItem` via KVO (`playbackBufferEmpty`, `playbackLikelyToKeepUp`, etc.), que é
  independente da UI do AVKit.
- Orientação geral da HIG (não específica de tvOS, vale para "Playing video" em todas as
  plataformas): evitar qualquer tela de carregamento se o conteúdo carrega rápido; se
  for inevitável e durar mais de ~2 segundos, preferir uma tela preta com um spinner de
  atividade centralizado — não inventar uma UI de loading própria mais chamativa que
  isso.

---

## 8. Foco (Focus Engine) e paralaxe

- tvOS usa o **Focus Engine**: navegação baseada em mover o foco entre componentes
  focalizáveis via remote/controle/teclado; focar e selecionar são gestos **separados**
  (mover foco não ativa o item — só o gesto de "escolher" ativa).
- Cada elemento focalizável pode estar em até **5 estados visuais distintos**:
  - **Unfocused** — aparência normal, menos proeminente.
  - **Focused** — se destaca via elevação (paralaxe/scale/sombra) e animação.
  - **Highlighted** — feedback instantâneo no momento exato do clique/seleção.
  - **Selected** — já escolhido/ativado.
  - **Unavailable** — não pode receber foco nem ser escolhido; aparência inativa.
- O efeito padrão do sistema ao ganhar foco é um **glow de borda suave** que cresce ao
  redor do item, **leve aumento de escala**, **sombra sutil**, animado com o timing
  padrão da plataforma (a Apple não publica a curva/duração exata como número público;
  implementações de referência de terceiros que tentam replicar usam algo na faixa de
  1.05×-1.1× de escala e sombra com offset vertical grande e blur generoso, mas isso é
  engenharia reversa de terceiros, não valor oficial).
- Como focar aumenta a escala do item, é preciso fornecer assets já pensados pro tamanho
  focado maior (para não ficarem borrados) e garantir espaçamento suficiente entre itens
  focalizáveis para o aumento não atropelar itens vizinhos.
- **Regra específica para telas full-screen** (o caso do player em si): a Apple recomenda
  explicitamente deixar os gestos do remote agirem sobre o **conteúdo** — porque em
  tela cheia não existe item "focado" visualmente, então o usuário assume que o gesto
  afeta o vídeo (scrub, skip), não algum estado de foco invisível. É por isso que a
  transport bar/tabs, quando aparecem sobre o vídeo, é que passam a ter foco navegável
  nos seus botões — o vídeo em si nunca é um item "focável" per se.

---

## 9. Animações e timing padrão

- **Auto-hide da transport bar**: os controles (barra de tempo, ícones) somem sozinhos
  depois de aproximadamente **5 segundos** parado/pausado sem interação — valor
  reportado de forma consistente por múltiplas fontes de terceiros como o comportamento
  padrão observável (não há constante pública documentada pela Apple para isso). Nota:
  o próprio fork já usa `KSOptions.animateDelayTimeInterval = 5` segundos
  (`Sources/KSPlayer/Video/VideoPlayerView.swift:940`) — ou seja, esse valor específico
  já está alinhado ao padrão nativo, mesmo sem ter sido escolhido com essa referência em
  mente.
- **Delegate de transição da transport bar**:
  `playerViewController(_:willTransitionToVisibilityOfTransportBar:with:)` — recebe um
  `AVPlayerViewControllerAnimationCoordinator` para sincronizar animação própria com a
  transição nativa de mostrar/esconder a barra.
- **Transições de tela cheia**: `playerViewController(_:willBeginFullScreenPresentationWithAnimationCoordinator:)`
  e `...willEndFullScreenPresentationWithAnimationCoordinator:` — ambos recebem um
  `UIViewControllerTransitionCoordinator` padrão do UIKit.
- **Dismissal do player**: `playerViewControllerShouldDismiss(_:)` (pergunta antes),
  `playerViewControllerWillBeginDismissalTransition(_:)` e
  `playerViewControllerDidEndDismissalTransition(_:)` (avisos do ciclo de vida da
  transição de saída).
- **Picture in Picture**: ciclo completo de delegate —
  `playerViewControllerWillStartPictureInPicture` →
  `playerViewControllerDidStartPictureInPicture` (e o par simétrico
  `WillStop`/`DidStop`), mais `failedToStartPictureInPictureWithError` e
  `restoreUserInterfaceForPictureInPictureStopWithCompletionHandler` para devolver a UI
  ao normal.
- **Conteúdo intersticial** (avisos legais, anúncios): `playerViewController(_:willPresent:)`
  / `playerViewController(_:didPresent:)` marcam início/fim; combinado com
  `requiresLinearPlayback = true` durante essa janela, o usuário fica impedido de
  pular/arrastar até o intersticial acabar.

---

## 10. Legendas/closed captions — aparência do sistema

Fora do escopo estrito da UI do player em si, mas é o mesmo sistema que desenha o texto
sobre o vídeo: `Ajustes > Acessibilidade > Legendas > Estilo` permite customizar fonte,
tamanho, cor do texto, cor/opacidade do fundo, opacidade do texto, edge style e
highlight — e qualquer app usando as APIs padrão de legenda do AVKit herda esse estilo
automaticamente. Desde tvOS 26.4, o próprio botão de legenda (ícone de "balão de fala")
na transport bar ganhou um atalho rápido de estilo (tamanho + contorno/fundo
transparente) sem precisar sair para os Ajustes do sistema. Isso já está mapeado como
gap próprio no roadmap (`context/roadmap/use-system-caption-appearance.md`); citado aqui
só para reafirmar que é o mesmo motor de renderização de texto que o resto da UI nativa
usa, não um componente à parte.

---

## 11. Referência rápida — APIs públicas por categoria

| Categoria | Símbolo |
|---|---|
| Metadados/title view | `AVPlayerItem.externalMetadata`, `AVMetadataItem`, `transportBarIncludesTitleView` |
| Transport bar | `transportBarCustomMenuItems`, `playbackControlsIncludeTransportBar`, `player.speeds` |
| Content tabs | `customInfoViewControllers`, `infoViewActions`, `playbackControlsIncludeInfoViews`, `AVPlayerItem.navigationMarkerGroups` (`AVNavigationMarkersGroup`) |
| Up Next / proposta de conteúdo | `AVPlayerItem.nextContentProposal`, `AVContentProposal` |
| Contextual actions | `contextualActions` |
| Overlays customizados | `customOverlayViewController`, `contentOverlayView`, `unobscuredContentGuide` |
| Restrição de navegação | `requiresLinearPlayback`, `AVPlayerItem.interstitialTimeRanges` (`AVInterstitialTimeRange`) |
| Channel flipping (live) | `playerViewController(_:skipToNextChannel:)`, `...skipToPreviousChannel:`, `nextChannelInterstitialViewController(for:)`, `previousChannelInterstitialViewController(for:)` |
| Navegação de seek | `playerViewController(_:timeToSeekAfterUserNavigatedFrom:to:)`, `...willResumePlaybackAfterUserNavigatedFrom:to:` |
| Transição/animação | `playerViewController(_:willTransitionToVisibilityOfTransportBar:with:)`, `AVPlayerViewControllerAnimationCoordinator`, `...willBeginFullScreenPresentationWithAnimationCoordinator:`, `...willEndFullScreenPresentationWithAnimationCoordinator:` |
| Dismissal | `playerViewControllerShouldDismiss(_:)`, `...WillBeginDismissalTransition(_:)`, `...DidEndDismissalTransition(_:)` |
| Picture in Picture | `playerViewControllerWillStartPictureInPicture(_:)`, `...DidStartPictureInPicture(_:)`, `...WillStopPictureInPicture(_:)`, `...DidStopPictureInPicture(_:)`, `...failedToStartPictureInPictureWithError:`, `...restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:` |
| Seleção de mídia (áudio/legenda) | `playerViewController(_:didSelect:in:)` (`AVMediaSelectionOption`/`AVMediaSelectionGroup`) |
| Autorização parental | `AVPlayerItem.requestPlaybackRestrictionsAuthorization(completionHandler:)` |

---

## Referências

- Apple Developer Documentation — [Customizing the tvOS Playback Experience](https://developer.apple.com/documentation/avkit/customizing-the-tvos-playback-experience)
- Apple Developer Documentation — [`AVPlayerViewController`](https://developer.apple.com/documentation/avkit/avplayerviewcontroller)
- Apple Developer Documentation — [`AVPlayerViewControllerDelegate`](https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate)
- Apple Developer Documentation — [`AVContentProposal`](https://developer.apple.com/documentation/avkit/avcontentproposal)
- Apple Human Interface Guidelines — [Playing video](https://developer.apple.com/design/human-interface-guidelines/playing-video)
- Apple Human Interface Guidelines — [Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos)
- Apple Human Interface Guidelines — [Remotes](https://developer.apple.com/design/human-interface-guidelines/remotes)
- Apple Human Interface Guidelines — [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- Apple Human Interface Guidelines — [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- Apple Human Interface Guidelines — [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- Apple Human Interface Guidelines — [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- Apple Support — [Control what's playing on Apple TV](https://support.apple.com/en-gb/guide/tv/atvb7944597f/15.0/tvos/15.0)
- Apple Support — [Use subtitles and captioning in the Apple TV app](https://support.apple.com/guide/tvapp/activate-subtitles-and-captioning-atvb5ca42eb9/web)
- Apple Developer — HTTP Live Streaming (HLS) Authoring Specification for Apple devices — https://developer.apple.com/documentation/http-live-streaming/hls-authoring-specification-for-apple-devices
- WWDC 2016, Session 506 — "AVKit on tvOS" — https://developer.apple.com/videos/play/wwdc2016/506/ (transcrição: https://nonstrict.eu/wwdcindex/wwdc2016/506/ e https://asciiwwdc.com/2016/sessions/506)
- WWDC 2019, Session 503 — "Delivering Intuitive Media Playback with AVKit" — https://developer.apple.com/videos/play/wwdc2019/503/ (transcrição: https://asciiwwdc.com/2019/sessions/503)
- WWDC 2021, Session 10191 — "Deliver a great playback experience on tvOS" — https://developer.apple.com/videos/play/wwdc2021/10191/ (transcrição: https://nonstrict.eu/wwdcindex/wwdc2021/10191/)
- WWDC 2022, Session 10147 — "Create a great video playback experience" — https://developer.apple.com/videos/play/wwdc2022/10147/
- AppleInsider — "tvOS 26 hands on: Sleek Liquid Glass redesign, new Control Center and more" — https://appleinsider.com/articles/25/06/18/tvos-26-hands-on-sleek-liquid-glass-redesign-new-control-center-and-more
- AppleInsider — "tvOS 26 review: High on polish, light on new features for Apple TV" — https://appleinsider.com/articles/25/09/14/tvos-26-review-high-on-polish-light-on-new-features-for-apple-tv (inclui o comentário de terceiro sobre queda de contraste na scrub bar)
- MacRumors — "tvOS 26 Liquid Glass Redesign Excludes Older Apple TV Models" — https://www.macrumors.com/2025/06/09/tvos-26-liquid-glass-redesign-older-models/
- MacRumors — "tvOS 26 Now Available With Liquid Glass UI and Enhanced Apple TV Features" — https://www.macrumors.com/2025/09/15/apple-releases-tvos-26/
- FlatpanelsHD — "Mini-review of tvOS 26 for Apple TV: Liquid Glass and new features" — https://www.flatpanelshd.com/news.php?subaction=showfull&id=1757926503
- Gear Patrol — "Your Apple TV Just Got a Simple Yet Useful New Ability" (tvOS 26.4, atalho de estilo de legenda) — https://www.gearpatrol.com/tech/apple-tv-tvos-26-4-subtitle-styling/
- Fabernovel — "Video playback on iOS & tvOS" — https://fabernovel.github.io/2020-11-27/video_playback_on_ios_tvos
- Bitmovin Community — "Bitmovin Player now supports the latest tvOS15+ playback experience features" — https://community.bitmovin.com/t/bitmovin-player-now-supports-the-latest-tvos15-playback-experience-features/1301
- Apple Developer Forums — "tvOS: Video scrubbing UI" (confirma dependência de I-frame playlist para thumbnail) — https://developer.apple.com/forums/thread/25779
- `context/roadmap/progressbar-preview.md` e `context/roadmap/use-system-caption-appearance.md` (este repositório) — roadmaps já existentes que este documento cruza/reafirma do lado "o que é nativo de graça".
