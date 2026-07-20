# ROADMAP — Lumen (fork GPL do KSPlayer) para o StreamHub

**Objetivo:** levar este fork à paridade com o KSPlayer pago e com o Infuse **no que importa para o StreamHub** (app tvOS pessoal que toca streams HTTP de debrid — remuxes/WEB-DL 4K em MKV e anime com legendas ASS):

- **Qualidade:** Dolby Vision nativo via remux MKV→HLS local→AVPlayer, HDR10+ dinâmico, Atmos nativo, FFmpeg 8.x.
- **Usabilidade:** seek com preview, troca de stream sem delay, buffering/precache, legendas ASS/fontes embutidas perfeitas, aparência de legenda nativa do sistema.

Tudo fora desses dois pilares vai para o Icebox — pode ser promovido depois, mas não ocupa o caminho crítico agora.

**Contexto estrutural:** a migração aconteceu — o StreamHub toca playback pelo player nativo deste fork (rota nativa no `PlaybackCoordinator` com fallback para Infuse, `NativePlayerView`, `ProAVPlayer` como primeiro engine), consumindo o pacote via SPM remoto. O marco [[migracao-streamhub]] fechou, e com ele caiu o gate que segurava o benefício ao usuário das tasks de usabilidade: [[zero-delay]] e [[seek-ram]] sobem de fila.

Cada task referencia seu doc de pesquisa em `context/roadmap/`. Referências de linha (`arquivo.swift:123`) são as da data da pesquisa — revalidar contra o código ao pegar a task.

---

## ✅ Entregue (baixa em lote, 2026-07-19)

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

**Preparação transversal (item leve, não conta no WIP):** [[sample-library]] — biblioteca curada de amostras de teste. O que ainda falta e para quê: E-AC-3 JOC (WEB-DL) para [[atmos-dec3]]; DV P5 (`dvhe.05.06`), P8.1 e P7 MEL/FEL para [[dv-nativo]]; HDR10+ para [[hdr10plus]]; TrueHD 7.1 Atmos para validar o transcode FLAC entregue. Catálogo com fonte pública, spec exata e comandos mediainfo/ffprobe em [context/samples/SAMPLES.md](context/samples/SAMPLES.md); placeholders `<preencher>` dependem do acervo do dono.

### 1. [[atmos-dec3]] Sinalização Atmos no remux (dec3/JOC)

- **Objetivo:** fazer o caminho ProAVPlayer declarar Atmos de ponta a ponta — box `dec3` com `complexity_index_type_a` no init segment (fix do movenc presente no FFmpeg ≥ 8.0, já embarcado) e atributo `CHANNELS="…/JOC"` na playlist — para o receiver acender o logo Atmos.
- **Critério de aceite:** amostra E-AC-3 JOC remuxada acende Atmos no receiver; inspeção do `dec3` no fMP4 de saída confirma o `complexity_index_type_a` (método estabelecido no spike); E-AC-3 sem JOC e demais codecs continuam tocando sem regressão.
- **Arquivos-alvo:** `ProAVPlaylist.swift:61-92` (aposentar o case `copyAwaitingFFmpeg8AtmosDEC3`, emitir os atributos); validação sobre `ProAVRemuxSession`.
- **Dificuldade:** S
- **Dependências:** nenhuma — [[ffmpeg-8x]] entregue destravou. Amostra via [[sample-library]]. É a task mais barata com maior retorno de qualidade sonora do fluxo.
- **Pesquisa:** [context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md) (método de inspeção do `dec3`) e [context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md](context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md)

### 2. [[dv-nativo]] Dolby Vision dynamic metadata nativo — P5/P8 passthrough + P7→P8.1

- **Objetivo:** sobre o pipeline ProAVPlayer entregue, preservar/remontar o box `dvcC`/`dvvC` e o RPU no remux para que o VideoToolbox aplique o tone-mapping dinâmico real da Dolby, convertendo P7 dual-layer para P8.1 single-layer (padrão `dovi_tool` mode 2). É o maior salto de qualidade visual disponível: hoje a TV entra em modo DV, mas o tone-mapping é estático.
- **Critério de aceite:** amostra P5 e P8.1 tocam via `master.m3u8` com a TV reportando Dolby Vision e metadata dinâmico ativo (validação visual lado a lado com Infuse/app nativo); amostra P7 (MEL e FEL) converte para P8.1 e toca nativamente; sinalização HLS (`VIDEO-RANGE=PQ`, codec `dvh1.0X`) gerada a partir do `DOVIDecoderConfigurationRecord` já parseado.
- **Arquivos-alvo:** `FFmpegAssetTrack.swift:180,228-229` (serializar `dvcC`/`dvvC` — hoje só `hvcC` é escrito); `VideoToolboxDecode.swift:202-216`; `MEPlayerItem.swift:271-326` (remux); novo conversor P7→P8 (`libdovi` vendorizado como rota default; porta própria da lógica mode 2 do `dovi_tool` só como plano B).
- **Dificuldade:** L→XL — reescrever RPU exige parse e reserialização de bitstream (emulation prevention, CRC32).
- **Dependências:** [[proavplayer]] entregue — desbloqueada. **Primeiro passo obrigatório:** verificar os bsfs DOVI no binário MPVKit embarcado (`nm` sobre os xcframeworks — `dovi_rpu` é documentado no FFmpeg 8.x, `dovi_split` não está confirmado; herança do aceite de [[ffmpeg-8x]], que fechou por outra rota sem essa verificação). Se não existirem, `libdovi` deixa de ser alternativa e vira obrigatório. Amostras via [[sample-library]].
- **Pesquisa:** [context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md](context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md)

### 3. [[zero-delay]] Troca de stream sem delay

- **Objetivo:** eliminar o gap perceptível ao trocar de URL/candidato de stream (dub↔leg, qualidade, fallback), substituindo o padrão atual de shutdown síncrono + reopen por prewarm/pre-roll/hot-swap em camadas. Maior dor de UX visível hoje: o usuário vê tela preta a cada troca.
- **Critério de aceite:** trocar de candidato preservando `currentPlaybackTime` sem tela preta/spinner — o frame atual só é solto quando o novo pipeline tem primeiro frame decodificado e áudio pronto; camada 1 (prewarm DNS/TCP) mensurável nas métricas `KSOptions.dnsStartTime`/`tcpStartTime` existentes; camada 2 (`AVQueuePlayer.insert(_:after:)`) cobre o caminho HLS-remux→AVPlayer.
- **Arquivos-alvo:** `KSPlayerLayer.swift:128-159,318-330` (caminho "switch sem stop"); `KSMEPlayer.swift:317-334` (inverter shutdown-antes-de-abrir); `KSAVPlayer.swift:300-324,448-453`; `MEPlayerItem.swift` (duas instâncias vivas — auditar retain cycle do close e estáticos); backends de áudio (reconfiguração de formato em runtime).
- **Dificuldade:** L (MVP restrito ao motor AVPlayer: M — começar por ele: candidatos HLS locais do ProAVPlayer são baratos de pré-rolar)
- **Dependências:** **desbloqueada** — [[migracao-streamhub]] entregue (o player nativo é o motor real do StreamHub) e [[proavplayer]]/[[precache-disco]] entregues reduzem o custo. Incógnita a validar: limite de sessões VideoToolbox simultâneas no tvOS.
- **Pesquisa:** [context/roadmap/video-switching-with-zero-delay.md](context/roadmap/video-switching-with-zero-delay.md)

### 4. [[seek-ram]] Memory cache para seek rápido em janela curta

- **Objetivo:** parar de descartar o buffer de ~30s já em RAM a cada seek — camada 1: seek pra frente dentro da janela já bufferizada sem tocar rede; camada 2: anel de retenção por trilha (tempo+bytes, alinhado a keyframe) para seek curto pra trás instantâneo.
- **Critério de aceite (escopo do Agora = camada 1):** seek de +10s/+30s dentro da janela bufferizada não chama `avformat_seek_file` nem gera requisição de rede, e o accurate-seek existente entrega o frame certo; seek longo cai no caminho de rede atual sem regressão. Camada 2 (seek de -10s em <200ms sem rede, orçamento de RAM respeitado em remux 4K de 80-100 Mbps) segue como extensão da própria task depois da camada 1 validada.
- **Arquivos-alvo:** `MEPlayerItem.swift:449-518` (decisão de pular o seek de rede); `MEPlayerItemTrack.swift:72-82,145-153,263-270` (reaproveitar accurate-seek, não descartar filas); novo `MEPlayer/PacketSeekCache.swift` (camada 2); `KSOptions.swift` (janela/teto de bytes).
- **Dificuldade:** S-M (camada 1) / L (camada 2)
- **Dependências:** **desbloqueada** — [[migracao-streamhub]] entregue. Invalidar o anel em ABR/loop gapless. Coordenação obrigatória com [[zero-delay]] (ambas mexem em `MEPlayerItem` — threading frágil, docs/03); sinergia com o scrub preview entregue (consultar o anel antes de abrir rede para thumbnail).
- **Pesquisa:** [context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md](context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md)

---

## ⏭️ Próximo

Ordenado por desbloqueio.

**Housekeeping transversal (item leve, não conta no WIP):** primeira release taggeada do lumen-player (hoje só dá para depender da branch `main` — o `.xcodeproj` do StreamHub inclusive resolve por branch) e annotations de availability honestas (`Package.swift` declara tvOS 13, a UI SwiftUI exige 16 — o floor é imposto em runtime, não pelo compilador).

### 5. [[hdr10plus]] HDR10+ dynamic metadata

- **Objetivo:** entregar tone-mapping dinâmico HDR10+ via passthrough do remux HLS local (estratégia A — o tvOS 16+/Apple TV 4K 3ª gen aplica sozinho; não existe API pública para entregar ST 2094-40 ao compositor a partir do MEPlayer).
- **Critério de aceite:** amostra HDR10+ tocando via ProAVPlayer (`VIDEO-RANGE=PQ`) ativa o modo HDR10+ na TV (validação visual/OSD da TV); conteúdo HDR10+ fora do remux continua com o fallback estático atual (HDR10) sem regressão.
- **Arquivos-alvo:** estratégia A: nenhum código HDR novo neste pacote — é validação sobre o ProAVPlayer entregue (o remux stream-copia o SEI). Estratégia B (tone-map manual da curva Bezier no shader Metal, só para o caminho MEPlayer): **adiar até medir** que fração real do catálogo de debrid carrega HDR10+ e cai fora do remux.
- **Dificuldade:** S (estratégia A, validação) / L (estratégia B, se algum dia se justificar)
- **Dependências:** **desbloqueada** — [[proavplayer]] entregue. Só precisa de amostra ([[sample-library]]) e hardware. Candidata natural a subir para o Agora quando abrir vaga no WIP.
- **Pesquisa:** [context/roadmap/hdr10-dynamic-metadata.md](context/roadmap/hdr10-dynamic-metadata.md)

### 6. [[read-ahead]] Precache à frente do playhead (read-ahead do DiskByteCache)

- **Objetivo:** preencher o `DiskByteCache` à frente do playhead em background (janela configurável), para que quedas curtas de rede não cheguem à tela e seeks longos pra frente encontrem bytes em disco — o cache entregue só busca sob demanda.
- **Critério de aceite:** com a janela pré-carregada e a rede artificialmente degradada por N segundos, o playback não rebufferiza; o fetch de read-ahead tem prioridade menor que o fluxo principal (sem competição de banda mensurável); teto de banda/bytes configurável respeitado; quota e eviction LRU existentes intactas.
- **Arquivos-alvo:** `Cache/DiskByteCache.swift`, `Cache/DiskCacheURLReader.swift` (agendador de fetch à frente da última leitura); `KSOptions` (janela/teto).
- **Dificuldade:** M
- **Dependências:** nenhuma — [[precache-disco]] entregue é a base. Papel complementar a [[seek-ram]]: RAM cobre a janela curta, disco cobre a longa. Atenção ao custo contra endpoints de debrid com rate limit.
- **Pesquisa:** [context/roadmap/precache-data-to-hard-drive.md](context/roadmap/precache-data-to-hard-drive.md) — atualizar com a seção de read-ahead ao pegar a task.

---

## 📦 Depois

### 7. [[libass]] Full ASS subtitle effects (render via libass)

- **Objetivo:** substituir o parser Swift aproximado por render ASS real via o produto `libass` já vendorizado no FFmpegKit (nunca ligado ao Swift), cobrindo `\move`/`\fad`/`\t`/`\clip`/`\p`/karaokê/rotação — fidelidade total de fansub.
- **Critério de aceite:** suíte de amostras reais de fansub de anime (karaokê, typesetting, sinais animados) renderiza visualmente igual ao mpv; animações fluidas (tick ligado ao `CADisplayLink`, não ao Timer de 10Hz); performance sustentada sobre vídeo 4K sem drops (compositor de `ASS_Image` eficiente, idealmente Metal).
- **Arquivos-alvo:** `Package.swift` (reativar produto `Libass`, hoje comentado); novo `Subtitle/LibassRenderer.swift`; `SubtitleDecode.swift`; `KSSubtitle.swift`; `KSPlayerLayer.swift` (tick de alta frequência); possível compositor Metal dedicado.
- **Dificuldade:** XL
- **Dependências:** [[fontes-embutidas]] **entregue** — pré-requisito de fidelidade satisfeito (extração reaproveitada, consumidor vira `ass_add_font`). Subsume "word-by-word subtitles" (Icebox). Incógnitas: module map do `libass.xcframework` do MPVKit e fontprovider (CoreText vs fontconfig). Sinergia com [[pip-legendas]]: se o render virar bitmap composto na layer de vídeo, legenda no PiP sai de graça.
- **Pesquisa:** [context/roadmap/full-ass-subtitle-effects-render-via-libass.md](context/roadmap/full-ass-subtitle-effects-render-via-libass.md)

### 8. [[caption-sistema]] Aparência de legenda do sistema (MediaAccessibility)

- **Objetivo:** toggle opt-in que aplica as prefs de Settings → Accessibility → Subtitles and Captioning do tvOS (cor, fonte, tamanho, edge style) ao overlay de legenda, via framework `MediaAccessibility` — mesmo caminho que o Infuse é obrigado a usar.
- **Critério de aceite:** com o toggle ligado, mudar o estilo em Settings reflete na legenda em tempo real (`kMACaptionAppearanceSettingsChangedNotification`); com o toggle desligado, comportamento atual intacto; UI deixa explícito que o toggle sobrescreve estilo ASS/fansub.
- **Arquivos-alvo:** `KSOptions.swift` (`usesSystemCaptionAppearance`); `KSSubtitle.swift` (derivar os estáticos + republicar em mudança de estilo); `KSVideoPlayerView.swift`; `VideoPlayerView.swift`; novo import `MediaAccessibility`.
- **Dificuldade:** M
- **Dependências:** nenhuma bloqueante. Incógnita: se os presets novos do tvOS 26.4 escrevem na mesma store clássica (só testável em hardware). Edge style `.uniform` (outline real) sem equivalente 1:1 em SwiftUI `Text` — melhor esforço documentado.
- **Pesquisa:** [context/roadmap/use-system-caption-appearance.md](context/roadmap/use-system-caption-appearance.md)

### 9. [[pip-legendas]] Legendas no Picture in Picture

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
