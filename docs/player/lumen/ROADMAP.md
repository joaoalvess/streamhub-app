# ROADMAP — Lumen (fork GPL do KSPlayer) para o StreamHub

**Objetivo:** levar este fork à paridade com o KSPlayer pago e com o Infuse **no que importa para o StreamHub** (app tvOS pessoal que toca streams HTTP de debrid — remuxes/WEB-DL 4K em MKV e anime com legendas ASS):

- **Qualidade:** Dolby Vision nativo via remux MKV→HLS local→AVPlayer, HDR10+ dinâmico, Atmos nativo, FFmpeg 8.x.
- **Usabilidade:** seek com preview, troca de stream sem delay, buffering/precache, legendas ASS/fontes embutidas perfeitas, aparência de legenda nativa do sistema.

Tudo fora desses dois pilares vai para o Icebox — pode ser promovido depois, mas não ocupa o caminho crítico agora.

**Contexto estrutural:** a migração aconteceu — o StreamHub toca playback pelo player nativo deste fork (rota nativa no `PlaybackCoordinator` com fallback para Infuse, `NativePlayerView`, `ProAVPlayer` como primeiro engine), consumindo o pacote via SPM remoto. O marco [[migracao-streamhub]] fechou, e com ele caiu o gate que segurava o benefício ao usuário das tasks de usabilidade. Em 2026-07-25 as quatro tasks do Agora foram executadas em lote (ver ✅ Entregue): o que restou delas — motor MEPlayer, anel de seek para trás e prewarm — é o novo caminho crítico.

Cada task referencia seu doc de pesquisa em `context/roadmap/`. Referências de linha (`arquivo.swift:123`) são as da data da pesquisa — revalidar contra o código ao pegar a task.

---

## ✅ Entregue

### Execução do kanban Agora (2026-07-25)

As quatro tasks do Agora foram executadas em lote (branch `task/agora-kanban` nos dois repos, lanes paralelas em worktrees). Relatório completo — commits, decisões, o que ficou de fora e como validar — em [context/exec/agora-resultado-2026-07-25.md](context/exec/agora-resultado-2026-07-25.md).

- **[[atmos-dec3]]** — `movflags` com `+delay_moov` (+ `use_editlist=0` para não perder o rebase de timestamps), nova fronteira do `init.mp4` via box-walk ISOBMFF (`ProAVInitBoundaryScanner`), gate que só libera o `moov` depois de um packet AC-3/E-AC-3 com syncword válido, detecção de JOC por `codecpar.profile` e `CHANNELS="16/JOC"` no `#EXT-X-MEDIA`; case `copyAwaitingFFmpeg8AtmosDEC3` aposentado. **Descoberta que mudou o escopo:** o `movenc` 8.x recusa escrever o `dec3` antes de parsear packets E-AC-3 — sem o `delay_moov` o header já falhava. Nada ficou de fora.
- **[[dv-nativo]]** — a parte de passthrough (P5/P8.1) não exigiu **nenhuma linha**: as três condições do `movenc` para escrever `dvcC`/`dvvC` já estavam satisfeitas desde o [[proavplayer]] (muxer `mp4`, side data no codecpar de saída, `strict_std_compliance=-2`). A conversão P7→P8.1 foi entregue: `DOVIPacketRewriter` dropa o NAL 63 e converte o RPU (NAL 62) com o **Libdovi 3.3.2 já vendorizado** (mode 2), override do registro DOVI de saída, signaling `dvh1.08.LL`, gate `KSOptions.convertDolbyVisionProfile7`, e falha explícita (→ `KSMEPlayer`) se nenhuma RPU aparecer. **Descobertas:** a lib cuida sozinha de emulation prevention e CRC32 (o risco XL da pesquisa não se materializou) e perfil 8 gera box **`dvvC`**, não `dvcC` — a inspeção do aceite tem que procurar `dvvC`. Ficou de fora: P7 em MPEG-TS (extradata Annex-B, recusado por design).
- **[[zero-delay]]** (camadas 1-2, motor AVPlayer) — `switchSource`/`cancelSourceSwitch` no `MediaPlayerProtocol`, hot swap por `AVQueuePlayer.insert(_:after:)` no `KSAVPlayer`, launch de remux paralelo no `ProAVPlayer` (que de quebra fechou a pendência antiga de fallback espúrio do [[proavplayer]]), `KSPlayerLayer.switchSource` sem `stop()` e sem `.preparing`, opt-in `KSOptions.isSourceSwitchEnabled`; no app, `switchNativeSource` preservando o `id` da sessão, migração do registro de progresso e roteamento por `contentKey`. Ficaram de fora: camadas 3/4 e o prewarm especulativo → tasks 1 e 4 abaixo.
- **[[seek-ram]]** (camada 1) — seek para frente dentro da janela de packets já bufferizada é servido da RAM: decisão na read thread, drenagem por identidade na decode thread, commit só depois de as trilhas confirmarem, e qualquer falha degrada para o `avformat_seek_file` atual. `KSOptions.isMemorySeekEnabled` (default ligado). Ficou de fora: camada 2 (anel para trás) → task 2 abaixo.

Validações manuais ainda pendentes dessas entregas (**nada foi compilado, testado nem pushado** — o build é do dono): logo Atmos no receiver e inspeção do `dec3`/`dvvC` no init segment; DV dinâmico real em P5/P8.1 lado a lado com Infuse; P7 MEL e FEL tocando como P8.1; seek +10s/+30s servido da RAM (log de hit sem tráfego de rede). E uma pendência que **não é de hardware**: o aceite de [[zero-delay]] não é exercitável ponta a ponta hoje porque o seletor de fontes não é alcançável com sessão nativa ativa (ver preparação transversal em 🎯 Agora).

### Baixa em lote (2026-07-19)

O kanban ficou defasado em relação ao código; conferido contra o repo do lumen-player (commits `b09ec4a`…`50ff53d`) e a integração no StreamHub. O que cada entrega deixou de fora virou task nova no fluxo abaixo.

- **[[spike-ffmpegkit-614]]** (2026-07-18) — refutou o 6.1.4 e promoveu o upgrade de FFmpeg; resultado em [context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md).
- **[[ffmpeg-8x]]** — FFmpeg 8.1.2 no ar, por rota diferente da planejada: FFmpegKit vendorizado no próprio repo consumindo xcframeworks prontos do MPVKit (`0.41.0-n8.1.2`), sem fork do kingslay nem build manual. Consequência: as flags de configure são as do MPVKit, e a verificação dos bsfs DOVI (`dovi_rpu`/`dovi_split`) prometida no aceite **não foi feita** — migra como primeiro passo de [[dv-nativo]].
- **[[proavplayer]]** — engine completo: remux fMP4 (`ProAVRemuxSession`), servidor HTTP loopback, playlists HLS, transcode TrueHD/DTS→FLAC, composição sobre `KSAVPlayer`. Ficaram de fora: sinalização Atmos (virou [[atmos-dec3]]) e o RPU/dvcC ([[dv-nativo]], como planejado).
- **[[dv-fase0]]** — P5 roteado ao pipeline IPT (`DisplayModel.swift`, commit `7b7ea7d`).
- **[[precache-disco]]** — `DiskByteCache` + pontes AVIO/resource loader, opt-in via `diskCacheDirectory`, quota com eviction LRU. Ficou de fora: read-ahead à frente do playhead (virou [[read-ahead]]).
- **[[fontes-embutidas]]** — `EmbeddedFontRegistry`, extração de anexos e registro CoreText (commit `7c53d53`).
- **[[progressbar-preview]]** — `ScrubThumbnailEngine` + `ThumbnailController` + popup de scrub na UI tvOS (tvOS-only).
- **[[migracao-streamhub]]** — rota nativa no `PlaybackCoordinator` com fallback Infuse automático e por título, resume de posição, Lumen via SPM remoto. **Abre os gates de [[zero-delay]] e [[seek-ram]].**

Validações manuais ainda pendentes dessas entregas (dependem de amostra/hardware — [[sample-library]] segue vivo): Atmos acendendo no receiver, DV real na TV lado a lado com Infuse, retorno do modo de vídeo (dynamic range/refresh rate) ao sair do playback.

---

## 🎯 Agora

Caminho crítico, ordenado por desbloqueio (o que destrava o quê). Máximo 3-5 tasks.

**Preparação transversal (itens leves, não contam no WIP):**

- [[sample-library]] — biblioteca curada de amostras de teste. O que ainda falta e para quê: E-AC-3 JOC (WEB-DL) para validar [[atmos-dec3]]; DV P5 (`dvhe.05.06`), P8.1 e P7 MEL/FEL para validar [[dv-nativo]]; HDR10+ para [[hdr10plus]]; TrueHD 7.1 Atmos para validar o transcode FLAC entregue. Catálogo com fonte pública, spec exata e comandos mediainfo/ffprobe em [context/samples/SAMPLES.md](context/samples/SAMPLES.md); placeholders `<preencher>` dependem do acervo do dono.
- **Seletor de fontes alcançável durante a reprodução** (novo, 2026-07-25) — o roteamento de troca de fonte no app está fiado e testado (`selectSource` → `switchNativeSource` por `contentKey`), mas o `SourcesModalView` vive numa subárvore com `.disabled(nativeSession != nil)`, então nenhum gesto abre o seletor com sessão nativa ativa. Enquanto não existir esse ponto de entrada (candidato: overlay do player, fora do `.disabled`), o aceite de [[zero-delay]] entregue e das tasks 1 e 4 abaixo **não é exercitável ponta a ponta**. Trabalho de UI no `streamhub-app`, não no player.

### 1. [[zero-delay-meplayer]] Troca de stream sem delay no motor MEPlayer (camadas 3/4)

- **Objetivo:** estender o hot swap entregue no motor AVPlayer para o `KSMEPlayer` (segundo engine, FFmpeg/Metal) e fazer o handoff de áudio sem gap, para que a troca sem tela preta valha também quando o ProAVPlayer não cobre a fonte.
- **Critério de aceite:** com `isSourceSwitchEnabled` ligada e o `KSMEPlayer` como engine ativo, trocar de candidato preserva o frame atual e a posição até o novo pipeline ter primeiro frame decodificado e áudio pronto; o backend de áudio reconfigura formato em runtime sem clique nem silêncio; falha do candidato degrada para o `set(url:options:)` atual sem regressão.
- **Arquivos-alvo:** `KSMEPlayer.swift` (hoje herda o default frio de `MediaPlayerProtocol.switchSource`, ou seja, cai no cold path); `MEPlayerItem.swift` (duas instâncias vivas — auditar retain cycle do close e estáticos); backends de áudio (`AudioEnginePlayer`/`AudioUnitPlayer`, reconfiguração de formato); `KSPlayerLayer.swift` (contrato de coalescing/cancelamento já pronto, só consumir).
- **Dificuldade:** L
- **Dependências:** [[zero-delay]] camadas 1-2 **entregue** — o contrato `switchSource`/`cancelSourceSwitch`, o coalescing por generation e o cancelamento real no engine já existem e são reaproveitados. Bloqueio de validação herdado: o seletor de fontes ainda não é alcançável durante a reprodução (preparação transversal acima). Coordenação obrigatória com a task 2 (ambas mexem em `MEPlayerItem` — threading frágil, docs/03; **não introduzir locks novos**). Incógnita ainda não medida: limite de sessões VideoToolbox simultâneas no tvOS.
- **Pesquisa:** [context/roadmap/video-switching-with-zero-delay.md](context/roadmap/video-switching-with-zero-delay.md) (com a seção de resultado das camadas 1-2)

### 2. [[seek-ram-anel]] Anel de retenção para seek curto para trás (camada 2)

- **Objetivo:** reter packets já consumidos por trilha (janela por tempo + teto de bytes, alinhada a keyframe) para que seek curto **para trás** seja servido da RAM — a metade que a camada 1 entregue não cobre.
- **Critério de aceite:** seek de −10s dentro da janela retida não chama `avformat_seek_file` nem gera requisição de rede e entrega o frame certo em <200 ms; teto de RAM respeitado em remux 4K de 80-100 Mbps; anel invalidado em troca de fonte, troca de trilha e loop gapless; seek fora da janela cai no caminho de rede atual sem regressão.
- **Arquivos-alvo:** novo `MEPlayer/PacketSeekCache.swift` (ou extensão do `CircularBuffer`, que já ganhou `peekEdges`/`scan`/`drain(upTo:)`/`wakeup` internos na camada 1); `MEPlayerItemTrack.swift` (`fastSeek`/`performMemorySeek` já existem e são o ponto de extensão); `MEPlayerItem.swift` (`isMemorySeekEligible`/`canServeSeekFromMemory` hoje exigem seek para frente); `KSOptions.swift` (janela/teto de bytes, ao lado de `isMemorySeekEnabled`).
- **Dificuldade:** L
- **Dependências:** [[seek-ram]] camada 1 **entregue**. **Descoberta da camada 1 que muda o desenho:** a render thread também consome a fila de packets de vídeo (`dropNextPacket`/`dropGOPPacket`), então reter e drenar tem que ser **por identidade**, não por contagem — e sem locks novos (docs/03). Coordenação obrigatória com a task 1 (mesmo arquivo, mesmo threading). Sinergia com o scrub preview entregue: consultar o anel antes de abrir rede para thumbnail.
- **Pesquisa:** [context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md](context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md) (com a seção de resultado da camada 1)

### 3. [[hdr10plus]] HDR10+ dynamic metadata

Promovida do Próximo em 2026-07-25, como o próprio card previa ("candidata natural a subir quando abrir vaga no WIP"): é validação sem código e pega carona na mesma bateria de hardware das entregas de [[atmos-dec3]] e [[dv-nativo]].

- **Objetivo:** entregar tone-mapping dinâmico HDR10+ via passthrough do remux HLS local (estratégia A — o tvOS 16+/Apple TV 4K 3ª gen aplica sozinho; não existe API pública para entregar ST 2094-40 ao compositor a partir do MEPlayer).
- **Critério de aceite:** amostra HDR10+ tocando via ProAVPlayer (`VIDEO-RANGE=PQ`) ativa o modo HDR10+ na TV (validação visual/OSD da TV); conteúdo HDR10+ fora do remux continua com o fallback estático atual (HDR10) sem regressão.
- **Arquivos-alvo:** estratégia A: nenhum código HDR novo — é validação sobre o ProAVPlayer entregue (o remux stream-copia o SEI). Estratégia B (tone-map manual da curva Bezier no shader Metal, só para o caminho MEPlayer): **adiar até medir** que fração real do catálogo de debrid carrega HDR10+ e cai fora do remux.
- **Dificuldade:** S (estratégia A, validação) / L (estratégia B, se algum dia se justificar)
- **Dependências:** **desbloqueada** — [[proavplayer]] entregue. Só precisa de amostra ([[sample-library]]) e hardware. Atenção: o remux mudou em 2026-07-25 (`+delay_moov`, `use_editlist=0`, init segment cortado no primeiro `moof`) — se a amostra HDR10+ não entrar em modo dinâmico, conferir antes se o passthrough do SEI sobreviveu a essa mudança.
- **Pesquisa:** [context/roadmap/hdr10-dynamic-metadata.md](context/roadmap/hdr10-dynamic-metadata.md)

### 4. [[prewarm-candidatos]] Prewarm especulativo de candidatos de stream

- **Objetivo:** começar DNS/TCP/TLS — e, no caminho ProAV, o próprio remux — do candidato provável **antes** de o usuário escolher, para que a troca de fonte commite na hora em vez de esperar os primeiros segmentos.
- **Critério de aceite:** com o seletor de fontes aberto, o candidato em foco chega com conexão (e, no ProAV, `master.m3u8`) pronta antes da seleção, mensurável nas métricas `KSOptions.dnsStartTime`/`tcpStartTime` existentes; a troca commita sem a rebobinada de 1-5 s medida nas camadas 1-2; sair do seletor cancela o prewarm sem deixar workspace órfão nem sessão de remux viva; com o prewarm desligado, comportamento atual intacto.
- **Arquivos-alvo:** `ProAVPlayer.swift` (`makeLaunch` já isola um launch por candidato — é o gancho pronto); `KSAVPlayer.swift` (candidato enfileirado no `AVQueuePlayer`); `KSOptions.swift` (teto de candidatos/janela); no app, `SourcesModalView`/`MediaWindowView` (informar qual candidato está em foco).
- **Dificuldade:** M
- **Dependências:** [[zero-delay]] camadas 1-2 **entregue** — o contrato de switch e o cancelamento real no engine são o pré-requisito, e o `startRemux` antecipado do ProAV já é meio caminho. Precisa do seletor de fontes alcançável durante a reprodução (preparação transversal acima). Incógnita: custo de RAM/CPU/VideoToolbox de manter um remux especulativo vivo no tvOS — o mesmo teto que a task 1 precisa medir.
- **Pesquisa:** [context/roadmap/video-switching-with-zero-delay.md](context/roadmap/video-switching-with-zero-delay.md) — cobre o switch, **não** o prewarm especulativo (item 8 do design em [context/exec/plano-agora-2026-07-25.md](context/exec/plano-agora-2026-07-25.md)); escrever a seção de prewarm no doc antes de executar (regras 5 e 6).

---

## ⏭️ Próximo

Ordenado por desbloqueio.

**Housekeeping transversal (item leve, não conta no WIP):** primeira release taggeada do lumen-player (hoje só dá para depender da branch `main` — o `.xcodeproj` do StreamHub inclusive resolve por branch) e annotations de availability honestas (`Package.swift` declara tvOS 13, a UI SwiftUI exige 16 — o floor é imposto em runtime, não pelo compilador).

### 5. [[read-ahead]] Precache à frente do playhead (read-ahead do DiskByteCache)

- **Objetivo:** preencher o `DiskByteCache` à frente do playhead em background (janela configurável), para que quedas curtas de rede não cheguem à tela e seeks longos pra frente encontrem bytes em disco — o cache entregue só busca sob demanda.
- **Critério de aceite:** com a janela pré-carregada e a rede artificialmente degradada por N segundos, o playback não rebufferiza; o fetch de read-ahead tem prioridade menor que o fluxo principal (sem competição de banda mensurável); teto de banda/bytes configurável respeitado; quota e eviction LRU existentes intactas.
- **Arquivos-alvo:** `Cache/DiskByteCache.swift`, `Cache/DiskCacheURLReader.swift` (agendador de fetch à frente da última leitura); `KSOptions` (janela/teto).
- **Dificuldade:** M
- **Dependências:** nenhuma — [[precache-disco]] entregue é a base. Papel complementar a [[seek-ram]] (camada 1 entregue) e a [[seek-ram-anel]]: RAM cobre a janela curta, disco cobre a longa. Atenção ao custo contra endpoints de debrid com rate limit.
- **Pesquisa:** [context/roadmap/precache-data-to-hard-drive.md](context/roadmap/precache-data-to-hard-drive.md) — atualizar com a seção de read-ahead ao pegar a task.

---

## 📦 Depois

### 6. [[libass]] Full ASS subtitle effects (render via libass)

- **Objetivo:** substituir o parser Swift aproximado por render ASS real via o produto `libass` já vendorizado no FFmpegKit (nunca ligado ao Swift), cobrindo `\move`/`\fad`/`\t`/`\clip`/`\p`/karaokê/rotação — fidelidade total de fansub.
- **Critério de aceite:** suíte de amostras reais de fansub de anime (karaokê, typesetting, sinais animados) renderiza visualmente igual ao mpv; animações fluidas (tick ligado ao `CADisplayLink`, não ao Timer de 10Hz); performance sustentada sobre vídeo 4K sem drops (compositor de `ASS_Image` eficiente, idealmente Metal).
- **Arquivos-alvo:** `Package.swift` (reativar produto `Libass`, hoje comentado); novo `Subtitle/LibassRenderer.swift`; `SubtitleDecode.swift`; `KSSubtitle.swift`; `KSPlayerLayer.swift` (tick de alta frequência); possível compositor Metal dedicado.
- **Dificuldade:** XL
- **Dependências:** [[fontes-embutidas]] **entregue** — pré-requisito de fidelidade satisfeito (extração reaproveitada, consumidor vira `ass_add_font`). Subsume "word-by-word subtitles" (Icebox). Incógnitas: module map do `libass.xcframework` do MPVKit e fontprovider (CoreText vs fontconfig). Sinergia com [[pip-legendas]]: se o render virar bitmap composto na layer de vídeo, legenda no PiP sai de graça.
- **Pesquisa:** [context/roadmap/full-ass-subtitle-effects-render-via-libass.md](context/roadmap/full-ass-subtitle-effects-render-via-libass.md)

### 7. [[caption-sistema]] Aparência de legenda do sistema (MediaAccessibility)

- **Objetivo:** toggle opt-in que aplica as prefs de Settings → Accessibility → Subtitles and Captioning do tvOS (cor, fonte, tamanho, edge style) ao overlay de legenda, via framework `MediaAccessibility` — mesmo caminho que o Infuse é obrigado a usar.
- **Critério de aceite:** com o toggle ligado, mudar o estilo em Settings reflete na legenda em tempo real (`kMACaptionAppearanceSettingsChangedNotification`); com o toggle desligado, comportamento atual intacto; UI deixa explícito que o toggle sobrescreve estilo ASS/fansub.
- **Arquivos-alvo:** `KSOptions.swift` (`usesSystemCaptionAppearance`); `KSSubtitle.swift` (derivar os estáticos + republicar em mudança de estilo); `KSVideoPlayerView.swift`; `VideoPlayerView.swift`; novo import `MediaAccessibility`.
- **Dificuldade:** M
- **Dependências:** nenhuma bloqueante. Incógnita: se os presets novos do tvOS 26.4 escrevem na mesma store clássica (só testável em hardware). Edge style `.uniform` (outline real) sem equivalente 1:1 em SwiftUI `Text` — melhor esforço documentado.
- **Pesquisa:** [context/roadmap/use-system-caption-appearance.md](context/roadmap/use-system-caption-appearance.md)

### 8. [[pip-legendas]] Legendas no Picture in Picture

- **Objetivo:** manter a legenda visível quando o vídeo vai para a janela PiP — hoje o overlay SwiftUI fica na janela do app e a legenda some do PiP (limitação exposta na correção do README, 2026-07-19).
- **Critério de aceite:** com PiP ativo, a legenda do conteúdo aparece dentro da janela PiP; sem PiP, o overlay atual fica intacto; troca de trilha de legenda durante PiP reflete na hora.
- **Arquivos-alvo:** a mapear na pesquisa — candidato: compor a legenda na layer de vídeo (`KSPlayerLayer`) em vez de overlay SwiftUI.
- **Dificuldade:** M (estimativa — revalidar na pesquisa)
- **Dependências:** promovida do Icebox por decisão do dono (2026-07-19); **doc de pesquisa a escrever antes da execução** (regra 5). Coordenar com [[libass]] — um compositor bitmap na layer resolve os dois.
- **Pesquisa:** a escrever em `context/roadmap/`.

---

## 🧊 Icebox

Fora do foco atual (qualidade DV/HDR10+/Atmos/FFmpeg 8.x + usabilidade de player). Podem ser promovidas no futuro — ao promover, escrever/atualizar o doc de pesquisa em `context/roadmap/` primeiro.

- **Cadeia de fallback com 3 engines** (novo, 2026-07-19) — hoje o fallback é de dois slots (`firstPlayerType`/`secondPlayerType`) e depois `.error`; generalizar para cadeia é robustez marginal — a dupla ProAVPlayer→KSMEPlayer cobre o catálogo alvo.
- **Legendas com efeitos HDR** (rebaixada do Depois) — fora da enumeração dos dois pilares (a diretriz pede legendas ASS/fontes embutidas perfeitas e aparência de legenda nativa do sistema, não brilho HDR de legenda); depende de API tvOS 26 sem precedente público, hardware atualizado e calibração sem resposta fechada; promovível por decisão explícita do dono (regra 5); pesquisa pronta em [context/roadmap/display-subtitles-with-hdr-effects.md](context/roadmap/display-subtitles-with-hdr-effects.md).
- **Audio Passthrough Output by Wi-Fi** (ausente) — exige receptor de hardware externo e contraria a experiência 100% no Apple TV; pesquisa pronta em [context/roadmap/audio-passthrough-output-by-wi-fi.md](context/roadmap/audio-passthrough-output-by-wi-fi.md).
- **Video upscaling** (ausente) — o catálogo alvo já é remux/WEB-DL 4K; fora dos dois pilares.
- **Video output to another screen** (ausente) — sem caso de uso num Apple TV fixo na sala.
- **Live streaming rewind viewing** (ausente) — StreamHub não toca live.
- **Blu-ray disc (ISO/DVD) playback** (ausente) — fonte é HTTP de debrid, não discos.
- **Simultaneous playback of separate audio and video URLs** (ausente) — sem caso de uso no catálogo atual.
- **Offline AI real-time subtitle generation and translation** (ausente) — legendas vêm do catálogo/fansub; fora dos pilares.
- **Play videos in small window in-app (resumable)** (parcial) — UX secundária, não citada na diretriz.
- **Dolby AC-4** (ausente) — codec raro no catálogo de debrid.
- **Swift Concurrency (async/await/actors no core)** (parcial) — refactor interno sem ganho direto de qualidade/usabilidade; alto risco no threading frágil do MEPlayer.
- **Hardware De-interlace** (parcial) — conteúdo alvo é progressivo.
- **AV1 hardware decoding** (ausente) — Apple TV atual não tem decode HW de AV1; nem o pipeline ProAVPlayer tem rota testada (perfil AV1 DV nunca validado por ninguém).
- **Word-by-word subtitles** (ausente) — subsumida por [[libass]] (karaokê nativo); não implementar em separado.
- **Text subtitle translation** (ausente) — fora dos pilares.
- **Record video clips at any time** (parcial) — a infra de remux já serve às joias da coroa; o recorte em si é fora do foco.
- **Smoothly play 8K or 120 FPS video** (parcial) — catálogo alvo é 4K/24fps.
- **Video download and format conversion** (parcial) — distinto de precache; "baixar para offline" não é o modelo do StreamHub.
- **External image subtitles (SUP)** (ausente) — raro; PGS embutido já coberto.
- **Main subtitles and secondary subtitles** (ausente) — nicho; não citado na diretriz.
- **Adjust saturation, brightness and contrast** (ausente) — a filosofia do projeto é fidelidade nativa, não ajuste manual.
- **Custom URL protocols (nfs/smb/UPnP)** (parcial) — a fonte do StreamHub é HTTP de debrid.
- **Low latency 4K live streaming (<200ms na LAN)** (parcial) — live está fora do escopo.

---

## Como atualizar este arquivo

1. **WIP limit:** `🎯 Agora` tem no máximo 3-5 tasks — sempre o caminho crítico. Só entra task nova quando outra sai (concluída ou rebaixada).
2. **Conclusão:** task concluída sai do kanban no mesmo commit que fecha o trabalho; registrar a entrega no commit message e atualizar `docs/README.md` (tabela de paridade) e o doc de pesquisa correspondente com o resultado real.
3. **Ordenação:** `Agora` e `Próximo` ficam ordenados por desbloqueio — a task que destrava mais coisas primeiro. Ao mover tasks, reordenar e renumerar.
4. **Foco:** só features dos dois pilares (qualidade DV/HDR10+/Atmos/FFmpeg 8.x + usabilidade) ocupam `Agora`/`Próximo`/`Depois`. Qualquer outra ideia entra no `🧊 Icebox` com uma linha de motivo — nunca direto no fluxo.
5. **Promoção do Icebox:** exige (a) decisão explícita do dono e (b) doc de pesquisa em `context/roadmap/` com as 5 seções (abordagem, arquivos, dependências, riscos, referências) antes de virar task.
6. **Formato de task:** nome com id `[[assim]]`, objetivo em 1 frase, critério de aceite verificável, arquivos-alvo, dificuldade (S/M/L/XL), dependências com links `[[task]]`, link para o doc de pesquisa. Sem esses campos a task não entra.
7. **Referências de linha envelhecem:** os `arquivo.swift:123` vêm da data da pesquisa; ao pegar uma task, revalidar contra o código atual antes de implementar (e corrigir o doc de pesquisa se divergiu).
8. **Dependências mudam de status:** quando uma incógnita listada se resolver (ex.: spike do FFmpegKit 6.1.4 confirmar/refutar o Atmos no `dec3`), atualizar a seção de dependências das tasks afetadas na hora — é isso que mantém a ordenação por desbloqueio honesta.
9. **Descobertas no meio do caminho** (bug novo, dependência oculta, mudança de API da Apple): registrar primeiro no doc de pesquisa da task, e refletir aqui só o que muda escopo/ordem/aceite.
