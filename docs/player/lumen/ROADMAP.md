# ROADMAP — Lumen (fork GPL do KSPlayer) para o StreamHub

**Objetivo:** levar este fork à paridade com o KSPlayer pago e com o Infuse **no que importa para o StreamHub** (app tvOS pessoal que toca streams HTTP de debrid — remuxes/WEB-DL 4K em MKV e anime com legendas ASS):

- **Qualidade:** Dolby Vision nativo via remux MKV→HLS local→AVPlayer, HDR10+ dinâmico, Atmos nativo, FFmpeg 8.x.
- **Usabilidade:** seek com preview, troca de stream sem delay, buffering/precache, legendas ASS/fontes embutidas perfeitas, aparência de legenda nativa do sistema.

Tudo fora desses dois pilares vai para o Icebox — pode ser promovido depois, mas não ocupa o caminho crítico agora.

**Contexto estrutural:** hoje o StreamHub delega 100% do playback ao Infuse externo (`PlaybackCoordinator` → deep link). As tasks de usabilidade que dependem do player em produção ([[zero-delay]], [[seek-ram]]) só se manifestam para o usuário quando o player nativo deste fork substituir o Infuse — essa migração é o marco que todo este roadmap serve, explicitada como task [[migracao-streamhub]] (Próximo); [[zero-delay]] e o benefício ao usuário de [[seek-ram]] ficam formalmente sequenciados atrás dela.

Cada task referencia seu doc de pesquisa em `context/roadmap/`. Referências de linha (`arquivo.swift:123`) são as da data da pesquisa — revalidar contra o código ao pegar a task.

---

## 🎯 Agora

Caminho crítico, ordenado por desbloqueio (o que destrava o quê). Máximo 3-5 tasks.

**Preparação transversal (item leve, não conta no WIP):** [[sample-library]] — biblioteca curada de amostras de teste, resolvida antes/em paralelo ao Agora. A suíte de testes do pacote é no-op e todo critério de aceite abaixo é validação manual que exige amostra específica; sem isso, cada task paga o custo de caçar amostra no meio da implementação. Lista exata: DV P5 (`dvhe.05.06`), DV P8.1 + E-AC-3 JOC (WEB-DL), DV P7 MEL e P7 FEL (remux Blu-ray), HDR10+, TrueHD 7.1 Atmos, DTS-HD MA, MKV de anime com ASS + fontes de fansub embutidas (karaokê/typesetting). Catálogo com fonte pública (URL) por amostra, spec técnica exata a conferir e comandos mediainfo/ffprobe prontos em [context/samples/SAMPLES.md](context/samples/SAMPLES.md); placeholders `<preencher: URL/caminho do debrid>` restantes (P7 MEL, remux Blu-ray real de P7 FEL, fansub real com KFX pesado, combo real DV P8.1+E-AC3 JOC WEB-DL) dependem do acervo pessoal do dono — preencher ao pegar a task correspondente.

**✅ [[spike-ffmpegkit-614]] concluído (2026-07-18)** — resultado em [context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md): (a) muxer `hls` **NÃO** habilitado no binário (símbolo `ff_hls_muxer` ausente; muxers `mov`/`mp4`/`mpegts` presentes), (b) encoder `flac` **SIM** (símbolo `ff_flac_encoder` presente — transcode TrueHD/DTS→FLAC viável já no 6.1.4), (c) remux E-AC-3 JOC **NÃO** preserva o `complexity_index_type_a` no `dec3` — o fix upstream (`movenc.c`, commit `ebcf2dcb2c42`, jun/2025) só existe a partir do FFmpeg 8.0. O spike refuta o 6.1.4 e promove [[ffmpeg-8x]] a primeiro do Agora. Validação comportamental no device (harness `startRecord`→fMP4 + inspeção do `dec3`) fica como confirmação opcional do dono — a evidência estática é suficiente para ordenar o roadmap.

### 1. [[ffmpeg-8x]] Upgrade FFmpeg 6.1.4 → 8.x (fork do FFmpegKit)

- **Objetivo:** criar fork próprio do `kingslay/FFmpegKit` com FFmpeg `n8.1.x` e apontar o `Package.swift` deste repo para ele, destravando o passthrough Atmos e o muxer `hls` do remux e alinhando o fork à base da versão paga.
- **Critério de aceite:** `Package.swift:46` pinado no fork novo; **flags de configure do fork incluem `--enable-muxer=hls`** (ausente no 6.1.4 — achado do spike) e mantêm `--enable-encoder=flac`; `swift build` limpo neste repo em tvOS/iOS/macOS; playback manual OK com MKV 4K HEVC/HDR10 e anime ASS do catálogo real; remux E-AC-3 JOC de teste preserva o `complexity_index_type_a` no `dec3` de saída, validado com o método estabelecido no spike ([context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md): harness `startRecord`→fMP4 + inspeção do `dec3`, ou `nm` sobre os xcframeworks novos — sem depender do muxer HLS de [[proavplayer]] estar pronto); produtos irmãos `libass`, `libfreetype`, `libfribidi` e `libharfbuzz` continuam presentes e resolvíveis via SPM no fork novo ([[libass]] e [[fontes-embutidas]] dependem deles); bsfs DOVI disponíveis verificados e registrados no doc de pesquisa de [[dv-nativo]] (`dovi_rpu` é documentado; a existência de `dovi_split` precisa ser confirmada).
- **Arquivos-alvo:** externo — fork de `kingslay/FFmpegKit` (`Plugins/BuildFFmpeg/main.swift` `"n6.1"`→`"n8.1.x"`, patch de `videotoolbox.c`, headers internos, flags de `configure` — incluir `--enable-muxer=hls`); neste repo — `Package.swift:46`, `Package.resolved`, e os ~12 arquivos de `Sources/KSPlayer/MEPlayer/*` que importam FFmpeg (recompilar e seguir os erros; código já usa `AVChannelLayout` moderno, blast radius reduzido).
- **Dificuldade:** L (build manual de horas, sem CI, sem rede de testes automatizada)
- **Dependências:** nenhuma técnica; [[spike-ffmpegkit-614]] **refutou** o suporte do 6.1.4 (sem muxer `hls`, sem Atmos no `dec3` — fix só no FFmpeg ≥ 8.0), então esta task é **pré-requisito duplo de [[proavplayer]]** (metade Atmos + segmentação HLS via muxer `hls`) e sobe para primeiro do Agora. Único trabalho do [[proavplayer]] não gated: transcode TrueHD/DTS→FLAC (encoder já presente no 6.1.4) e a alternativa de MVP com playlist m3u8 manual sobre o muxer `mp4` fragmentado existente (ver resultado do spike).
- **Pesquisa:** [context/roadmap/ffmpeg-version-bundled.md](context/roadmap/ffmpeg-version-bundled.md) · **Plano de execução pronto:** [context/roadmap/ffmpeg-8x-plano-de-fork.md](context/roadmap/ffmpeg-8x-plano-de-fork.md) (diff exato do fork, quebras verificadas no KSPlayer, hospedagem, passo a passo de build) e [context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md)

### 2. [[proavplayer]] ProAVPlayer — MKV → HLS fMP4 local → AVPlayer (DV + Atmos nativos)

- **Objetivo:** terceiro engine que remuxa MKV (stream-copy, sem reencode de vídeo) para HLS fMP4 servido por HTTP em loopback e delega a um `KSAVPlayer` interno, deixando o sistema aplicar Dolby Vision, HDR10+ e Atmos nativamente.
- **Critério de aceite:** um remux 4K MKV (HEVC DV P8.1 + E-AC-3 JOC) toca via `master.m3u8` com a Apple TV entrando em modo Dolby Vision real (não tone-map) e o logo Atmos acendendo no receiver; amostra TrueHD 7.1 Atmos transcodificada para FLAC toca lossless multicanal via AVPlayer, sem erro de channel layout (o transcode é a peça genuinamente nova — o fork nunca codificou nada); MKV de anime com legenda ASS embutida toca via `master.m3u8` com a legenda renderizando no overlay (o remux usa `-sn` e o AVPlayer não recebe trilhas de legenda — a legenda vem da leitura paralela do MKV original); cadeia de fallback `master.m3u8` → `playlist.m3u8` (SDR tone-mapped) → `KSMEPlayer` funciona quando a sinalização falha; seek/troca de trilha via relançamento do remux retomam o playback em <3s (segmentos `hls_time` de 1-2s + pre-roll), medidos com [[precache-disco]] ativo — sem ele este aceite de usabilidade fica gated em [[precache-disco]]; ao encerrar/sair do playback, a Apple TV retorna ao modo de vídeo anterior (dynamic range e refresh rate — bugs ainda abertos na issue upstream #875: TV presa em DV, refresh rate não revertido, Atmos falhando com TV em SDR).
- **Arquivos-alvo:** novo `Sources/KSPlayer/MEPlayer/KSProAVPlayer.swift` (compõe `KSAVPlayer`, implementa `MediaPlayerProtocol`); `MEPlayerItem.swift:271-326,531-542` (estender `startRecord` para muxer HLS fMP4); `KSOptions.swift:338-357` (variante de `updateVideo` que não rebaixa DV→HDR10); `FFmpegAssetTrack.swift`/`MediaPlayerProtocol.swift:153-162` (`DOVIDecoderConfigurationRecord` → tabela perfil→tags); novo servidor HTTP embarcado (FlyingFox ou GCDWebServer — nenhum no `Package.swift` hoje); capacidade nova de encode FFmpeg (FLAC) para TrueHD/DTS; novo componente de leitura paralela do MKV original para legendas/metadados (segundo contexto de demux apontado à URL de origem, sincronizado ao clock do `KSAVPlayer` — orquestração exigida pelo passo 8 e pela seção de riscos da pesquisa).
- **Dificuldade:** XL
- **Dependências:** **bloqueada em duas frentes por [[ffmpeg-8x]]** (resultado do spike, [context/roadmap/spike-ffmpegkit-614-resultado.md](context/roadmap/spike-ffmpegkit-614-resultado.md)): a metade **Atmos** exige FFmpeg ≥ 8.0 (fix do `complexity_index_type_a` no `dec3`, commit `ebcf2dcb2c42` de jun/2025, ausente do 6.1.4) e a segmentação **HLS** exige o muxer `hls` que o binário 6.1.4 não tem (adicionado nas flags do fork). Dá para adiantar sem o fork: transcode TrueHD/DTS→FLAC (encoder `flac` confirmado presente no 6.1.4) e, se valer o custo, um MVP de remux com playlist m3u8 manual em Swift sobre o muxer `mp4` fragmentado existente — sem Atmos até o fork chegar. [[precache-disco]] (promovida ao Agora) é quase pré-requisito de usabilidade — o aceite de latência de seek acima assume ela ativa. Amostras via [[sample-library]].
- **Pesquisa:** [context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md](context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md)

### 3. [[dv-fase0]] Dolby Vision Fase 0 — correção de cor P5 no pipeline Metal atual

- **Objetivo:** corrigir o tratamento monolítico de `.dolbyVision` no engine FFmpeg/Metal existente, roteando perfil 5 (IPT-PQc2) para o shader `displayYCCTexture` hoje órfão, eliminando o tint verde/roxo em conteúdo `dvhe.05`.
- **Critério de aceite:** amostra P5 (`dvhe.05.06`) exibe cores corretas no `KSMEPlayer` (sem tint roxo/verde dos issues upstream #771/#348); P8.1 continua exibindo a base HDR10 corretamente; `DynamicRange.transferFunction` retorna PQ (não HLG) para DV PQ; bug do primário azul em `FFmpegDecode.swift:113-114` corrigido.
- **Arquivos-alvo:** `FFmpegAssetTrack.swift:37`/`MediaPlayerProtocol.swift:153-162` (ler `dovi.dv_profile`/`dv_bl_signal_compatibility_id`, hoje nunca consultados); `PlayerDefines.swift:118-127` (`transferFunction`); `FFmpegDecode.swift:94-114`; `Shaders.metal:83-103` + `DisplayModel.swift:100-119` (ligar o pipeline IPT); `PixelBufferProtocol.swift`.
- **Dificuldade:** S-M (dias) — é bug fix de cor estática, **não** dynamic metadata; não confundir com a entrega de [[dv-nativo]].
- **Dependências:** nenhuma — independente de [[proavplayer]] e [[ffmpeg-8x]]; continua valendo depois deles como fallback (P7 e conteúdo fora do remux).
- **Pesquisa:** [context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md](context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md) (seção "Fase 0")

### 4. [[precache-disco]] Precache em disco (DiskByteCache)

- **Objetivo:** cache Swift-puro de bytes em disco (arquivo local + índice de intervalos), plugado via `AbstractAVIOContext` no MEPlayer e `AVAssetResourceLoaderDelegate` no KSAVPlayer — a rota nativa `cache:`/`async:` do FFmpeg está provadamente quebrada em tvOS (`/tmp` hardcoded em `file_open.c`) e não é o caminho.
- **Critério de aceite:** re-seek para trecho já assistido de um stream de debrid não gera requisição de rede (verificável por log/proxy); quota rígida com eviction LRU respeitada; app sobrevive a kill no meio de escrita sem corromper o índice (fallback transparente para rede); chave de cache estável por título (fornecida pelo app, não derivada da URL com token rotativo).
- **Arquivos-alvo:** novos `Sources/KSPlayer/Cache/DiskByteCache.swift`, `MEPlayer/DiskCacheAVIOContext.swift`, `AVPlayer/DiskCacheResourceLoader.swift`; `KSOptions.swift:38-40` (aposentar a flag morta `cache`, novas `diskCacheDirectory`/`diskCacheMaxBytes`/chave); `KSAVPlayer.swift:216,451` (`resourceLoader.setDelegate`).
- **Dificuldade:** L
- **Dependências:** nenhuma bloqueante (pode começar hoje); **destrava a usabilidade de [[proavplayer]]** (seek/troca de trilha relançam o remux e competem por banda — o aceite de latência de seek dele assume este cache ativo) e barateia [[zero-delay]]. Promovida ao Agora no lugar de [[progressbar-preview]] por isso. O remux HLS local já resolve precache de graça para o conteúdo que passar por ele.
- **Pesquisa:** [context/roadmap/precache-data-to-hard-drive.md](context/roadmap/precache-data-to-hard-drive.md)

---

## ⏭️ Próximo

Ordenado por desbloqueio.

### 5. [[fontes-embutidas]] Fontes embutidas no MKV para render de legendas

- **Objetivo:** extrair anexos `AVMEDIA_TYPE_ATTACHMENT` no demux, registrar via `CTFontManagerRegisterGraphicsFont` e resolver por family name E PostScript name nos pontos de `UIFont(name:)` do parser ASS.
- **Critério de aceite:** MKV de anime com fonte de fansub embutida renderiza a legenda ASS com a fonte correta (comparação visual com mpv/Infuse); **inclui obrigatoriamente** o fix de `KSSubtitle.swift:346-351` (hoje o estático global sobrescreve `.font` a cada tick — sem esse fix a feature inteira é código morto invisível); troca rápida de stream com a mesma fonte não crasha nem duplica registro; desregistro simétrico no `shutdown()`.
- **Arquivos-alvo:** `MEPlayerItem.swift:335-349` (novo ramo no loop de `createCodec`), `:628-654` (desregistro); novo `Subtitle/EmbeddedFontRegistry.swift` (tabela dupla de nomes, Sendable-safe); `KSParseProtocol.swift:242,253,261-262`; `KSSubtitle.swift:346-351` (fix do overwrite global); `KSOptions.swift` (`registerEmbeddedFonts`).
- **Dificuldade:** M
- **Dependências:** nenhuma bloqueante; **é a metade que sobrevive** se [[libass]] acontecer depois (extração 100% reaproveitada, só troca o consumidor para `ass_add_font`); é pré-requisito de fidelidade de [[libass]] — por isso vem antes das tasks bloqueadas desta seção.
- **Pesquisa:** [context/roadmap/use-fonts-embedded-in-the-video-to-render-subtitles.md](context/roadmap/use-fonts-embedded-in-the-video-to-render-subtitles.md)

### 6. [[seek-ram]] Memory cache para seek rápido em janela curta

- **Objetivo:** parar de descartar o buffer de ~30s já em RAM a cada seek — camada 1: seek pra frente dentro da janela já bufferizada sem tocar rede; camada 2: anel de retenção por trilha (tempo+bytes, alinhado a keyframe) para seek curto pra trás instantâneo.
- **Critério de aceite:** camada 1 — seek de +10s/+30s dentro da janela bufferizada não chama `avformat_seek_file` nem gera requisição de rede, e o accurate-seek existente entrega o frame certo; camada 2 — seek de -10s dentro da janela retida completa em <200ms sem rede; orçamento de RAM respeitado em remux 4K de 80-100 Mbps em hardware real; seek longo cai no caminho de rede atual sem regressão.
- **Arquivos-alvo:** `MEPlayerItem.swift:449-518` (decisão de pular o seek de rede); `MEPlayerItemTrack.swift:72-82,145-153,263-270` (reaproveitar accurate-seek, não descartar filas); novo `MEPlayer/PacketSeekCache.swift`; `KSOptions.swift` (janela/teto de bytes).
- **Dificuldade:** S-M (camada 1) / L (camada 2)
- **Dependências:** nenhuma técnica; **benefício ao usuário formalmente sequenciado atrás de [[migracao-streamhub]]** — fica no Próximo (e não no Depois, como [[zero-delay]]) porque é testável no demo do fork e barateia [[progressbar-preview]] (preview consulta o anel antes de abrir rede). Invalidar o anel em ABR/loop gapless. Coordenação obrigatória com quem mexer em `MEPlayerItem` ao mesmo tempo (threading frágil, docs/03).
- **Pesquisa:** [context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md](context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md)

### 7. [[progressbar-preview]] Preview de thumbnail no scrub (ProgressBar Preview)

- **Objetivo:** gerar thumbnail sob demanda no momento do scrub (padrão Infuse/mpv, sem pré-scan/BIF), nos dois engines, com popup sobre o slider do caminho SwiftUI/tvOS.
- **Critério de aceite:** ao pausar/scrubbar num stream HTTP de debrid real (com headers/token), o popup mostra thumbnail do ponto alvo em <1s por passo, sem derrubar nem travar o playback principal; funciona em MKV via `KSMEPlayer` e em HLS real (playlist completa/VOD) via `KSAVPlayer`; para conteúdo via [[proavplayer]], a fonte do thumbnail é o caminho FFmpeg sobre a URL de origem do MKV — o HLS local do remux é janela deslizante (`delete_segments`, `hls_list_size 6`) e `AVAssetImageGenerator` não alcança tempos fora da janela viva; seeks de preview obsoletos são coalescidos.
- **Arquivos-alvo:** `MediaPlayerProtocol.swift:96` (novo `thumbnailImage(at:)`); `KSAVPlayer.swift:388-397,573-591` (parametrizar por tempo, API async `image(at:)`, tolerância ±0.5-1s); `ThumbnailController.swift:24-132` (generalizar para "thumbnail near time" sobre `AVFormatContext` secundário persistente — **obrigatório** passar `options.formatContextOptions` na abertura, hoje `nil` na linha 49, falha contra debrid com header/token); `KSVideoPlayerView.swift:554-587` (popup + debounce sobre `ControllerTimeModel.currentTime`); `KSOptions.swift` (flags novas).
- **Dificuldade:** L
- **Dependências:** nenhuma bloqueante. **Gate de execução:** decisão de produto pendente com o dono — interação "pausar + passo esquerda/direita" (padrão Infuse tvOS) vs arrastar slider contínuo, muda o escopo da camada de UI; resolver antes de a task entrar em execução (default sugerido: pausar + passo, o padrão de mercado apontado pela pesquisa) e registrar no doc de pesquisa. Risco a validar cedo: custo de conexões HTTP extras contra o endpoint de debrid (rate limit). Sinergia futura com [[seek-ram]] (consultar o buffer antes de abrir rede).
- **Pesquisa:** [context/roadmap/progressbar-preview.md](context/roadmap/progressbar-preview.md)

### 8. [[migracao-streamhub]] Migração StreamHub — Infuse → player nativo deste fork

- **Objetivo:** StreamHub passa a tocar playback via este fork (rota nativa no `PlaybackCoordinator`, com fallback para Infuse) para um subconjunto definido do catálogo — o marco que faz o pilar de usabilidade se manifestar ao usuário.
- **Critério de aceite:** subconjunto definido do catálogo (proposta inicial: WEB-DL/remux sem DV + anime com ASS) toca fim a fim no StreamHub via este fork, com seleção de trilhas, resume de progresso por perfil e marcação de assistido funcionando; fallback para Infuse automático em erro de playback e acionável por título; critérios de expansão do subconjunto documentados (o que precisa estar verde para cada classe de conteúdo migrar).
- **Arquivos-alvo:** no StreamHub — `PlaybackCoordinator` (rota nativa ao lado do deep link Infuse), tela de player consumindo a API deste pacote; neste repo — nenhum obrigatório (consumo via SPM).
- **Dificuldade:** L
- **Dependências:** o subconjunto inicial (sem DV) pode migrar com o `KSMEPlayer` atual + [[dv-fase0]]; conteúdo DV/Atmos espera [[proavplayer]]. **É o gate formal do benefício ao usuário de [[seek-ram]], [[zero-delay]] e [[progressbar-preview]]** — sequenciá-las atrás desta.
- **Pesquisa:** context/roadmap/streamhub-infuse-to-native-player-migration.md — **a escrever antes da execução** (regra 6: mapa do `PlaybackCoordinator`, contrato de progresso por perfil, matriz de fallback).

### 9. [[dv-nativo]] Dolby Vision dynamic metadata nativo — P5/P8 passthrough + P7→P8.1

- **Objetivo:** dentro do pipeline do [[proavplayer]], preservar/remontar o box `dvcC`/`dvvC` e o RPU no remux para que o VideoToolbox aplique o tone-mapping dinâmico real da Dolby, convertendo P7 dual-layer para P8.1 single-layer (padrão `dovi_tool` mode 2).
- **Critério de aceite:** amostra P5 e P8.1 tocam via `master.m3u8` com a TV reportando Dolby Vision e metadata dinâmico ativo (validação visual lado a lado com Infuse/app nativo); amostra P7 (MEL e FEL) converte para P8.1 e toca nativamente; sinalização HLS (`VIDEO-RANGE=PQ`, codec `dvh1.0X`) gerada a partir do `DOVIDecoderConfigurationRecord` já parseado.
- **Arquivos-alvo:** `FFmpegAssetTrack.swift:180,228-229` (serializar `dvcC`/`dvvC` — hoje só `hvcC` é escrito); `VideoToolboxDecode.swift:202-216`; `MEPlayerItem.swift:271-326` (remux); novo conversor P7→P8 (`libdovi` vendorizado como rota default; porta própria da lógica mode 2 do `dovi_tool` só como plano B).
- **Dificuldade:** L→XL — re-dimensionar antes de prometer como fatia de [[proavplayer]]: reescrever RPU exige parse e reserialização de bitstream (emulation prevention, CRC32), ordem de grandeza acima das "poucas dezenas de linhas" estimadas na pesquisa; pode virar XL isolado.
- **Dependências:** **bloqueada por [[proavplayer]]** (é uma fatia dele); [[dv-fase0]] entrega o fallback para o que não passar pelo remux; o planejamento assume `libdovi` vendorizado como rota default — FFmpeg 8.x documenta o bsf `dovi_rpu`, mas a existência de `dovi_split` **não está verificada** (verificação faz parte do aceite de [[ffmpeg-8x]]; se não existir, o conversor próprio/`libdovi` deixa de ser alternativa e vira obrigatório). Amostras P5/P7 MEL/P7 FEL/P8.1 via [[sample-library]].
- **Pesquisa:** [context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md](context/roadmap/native-dolby-vision-dynamic-metadata-p5-p8-p7-single-layer.md)

### 10. [[hdr10plus]] HDR10+ dynamic metadata

- **Objetivo:** entregar tone-mapping dinâmico HDR10+ via passthrough do remux HLS local (estratégia A — o tvOS 16+/Apple TV 4K 3ª gen aplica sozinho; não existe API pública para entregar ST 2094-40 ao compositor a partir do MEPlayer).
- **Critério de aceite:** amostra HDR10+ tocando via [[proavplayer]] (`VIDEO-RANGE=PQ`) ativa o modo HDR10+ na TV (validação visual/OSD da TV); conteúdo HDR10+ fora do remux continua com o fallback estático atual (HDR10) sem regressão.
- **Arquivos-alvo:** estratégia A: nenhum código HDR novo neste pacote — é validação sobre [[proavplayer]]. Estratégia B (tone-map manual da curva Bezier no shader Metal, só para o caminho MEPlayer): `FFmpegDecode.swift:102-105`, `Model.swift:420-462`, `MetalRender.swift`, `Shaders.metal` — **adiar até medir** que fração real do catálogo de debrid carrega HDR10+ e cai fora do remux.
- **Dificuldade:** S (estratégia A, validação) / L (estratégia B, se algum dia se justificar)
- **Dependências:** **bloqueada por [[proavplayer]]** (estratégia A); se a estratégia B for revivida, desenhar a plumbing de "metadado dinâmico por frame → shader" junto com o trabalho DV para não duplicar.
- **Pesquisa:** [context/roadmap/hdr10-dynamic-metadata.md](context/roadmap/hdr10-dynamic-metadata.md)

---

## 📦 Depois

### 11. [[zero-delay]] Troca de stream sem delay

- **Objetivo:** eliminar o gap perceptível ao trocar de URL/candidato de stream (dub↔leg, qualidade, fallback), substituindo o padrão atual de shutdown síncrono + reopen por prewarm/pre-roll/hot-swap em camadas.
- **Critério de aceite:** trocar de candidato preservando `currentPlaybackTime` sem tela preta/spinner — o frame atual só é solto quando o novo pipeline tem primeiro frame decodificado e áudio pronto; camada 1 (prewarm DNS/TCP) mensurável nas métricas `KSOptions.dnsStartTime`/`tcpStartTime` existentes; camada 2 (`AVQueuePlayer.insert(_:after:)`) cobre o caminho HLS-remux→AVPlayer.
- **Arquivos-alvo:** `KSPlayerLayer.swift:128-159,318-330` (caminho "switch sem stop"); `KSMEPlayer.swift:317-334` (inverter shutdown-antes-de-abrir); `KSAVPlayer.swift:300-324,448-453`; `MEPlayerItem.swift` (duas instâncias vivas — auditar retain cycle do close e estáticos); backends de áudio (reconfiguração de formato em runtime).
- **Dificuldade:** L (MVP restrito ao motor AVPlayer: M)
- **Dependências:** **bloqueada por [[migracao-streamhub]]** (o benefício só se manifesta com o player nativo como motor real do StreamHub — hoje 100% Infuse); se beneficia de [[precache-disco]]; a camada 2 se apoia em [[proavplayer]] (candidatos HLS locais são baratos de pré-rolar — fazer nessa ordem reduz risco). Incógnita a validar: limite de sessões VideoToolbox simultâneas no tvOS.
- **Pesquisa:** [context/roadmap/video-switching-with-zero-delay.md](context/roadmap/video-switching-with-zero-delay.md)

### 12. [[libass]] Full ASS subtitle effects (render via libass)

- **Objetivo:** substituir o parser Swift aproximado por render ASS real via o produto `libass` já vendorizado no FFmpegKit (nunca ligado ao Swift), cobrindo `\move`/`\fad`/`\t`/`\clip`/`\p`/karaokê/rotação — fidelidade total de fansub.
- **Critério de aceite:** suíte de amostras reais de fansub de anime (karaokê, typesetting, sinais animados) renderiza visualmente igual ao mpv; animações fluidas (tick ligado ao `CADisplayLink`, não ao Timer de 10Hz); performance sustentada sobre vídeo 4K sem drops (compositor de `ASS_Image` eficiente, idealmente Metal).
- **Arquivos-alvo:** `Package.swift:24-26` (reativar produto `libass` — corrigir capitalização do comentário); novo `Subtitle/LibassRenderer.swift`; `SubtitleDecode.swift:22-33,89-135`; `KSSubtitle.swift:233-386`; `KSPlayerLayer.swift:175` (tick de alta frequência); possível compositor Metal dedicado.
- **Dificuldade:** XL
- **Dependências:** [[fontes-embutidas]] (pré-requisito de fidelidade — `ass_add_font`); tick de alta frequência; subsume "word-by-word subtitles" (Icebox) e parte de "legendas com efeitos HDR" (Icebox — compositor bitmap comum). Incógnitas: module map do binário `libass.xcframework` e fontprovider (CoreText vs fontconfig) só verificáveis baixando o pacote.
- **Pesquisa:** [context/roadmap/full-ass-subtitle-effects-render-via-libass.md](context/roadmap/full-ass-subtitle-effects-render-via-libass.md)

### 13. [[caption-sistema]] Aparência de legenda do sistema (MediaAccessibility)

- **Objetivo:** toggle opt-in que aplica as prefs de Settings → Accessibility → Subtitles and Captioning do tvOS (cor, fonte, tamanho, edge style) ao overlay de legenda, via framework `MediaAccessibility` — mesmo caminho que o Infuse é obrigado a usar.
- **Critério de aceite:** com o toggle ligado, mudar o estilo em Settings reflete na legenda em tempo real (`kMACaptionAppearanceSettingsChangedNotification`); com o toggle desligado, comportamento atual intacto; UI deixa explícito que o toggle sobrescreve estilo ASS/fansub.
- **Arquivos-alvo:** `KSOptions.swift:74-75` (`usesSystemCaptionAppearance`); `KSSubtitle.swift:280-290,334-358` (derivar os estáticos + republicar em mudança de estilo); `KSVideoPlayerView.swift:641-646`; `VideoPlayerView.swift:684-699`; novo import `MediaAccessibility`.
- **Dificuldade:** M
- **Dependências:** nenhuma bloqueante; coordenar com "legendas com efeitos HDR" (Icebox) se ela for promovida — mesmos estáticos de estilo (`SubtitleModel.textColor` — definir quem vence). Incógnita: se os presets novos do tvOS 26.4 escrevem na mesma store clássica (só testável em hardware). Edge style `.uniform` (outline real) sem equivalente 1:1 em SwiftUI `Text` — melhor esforço documentado.
- **Pesquisa:** [context/roadmap/use-system-caption-appearance.md](context/roadmap/use-system-caption-appearance.md)

---

## 🧊 Icebox

Fora do foco atual (qualidade DV/HDR10+/Atmos/FFmpeg 8.x + usabilidade de player). Podem ser promovidas no futuro — ao promover, escrever/atualizar o doc de pesquisa em `context/roadmap/` primeiro.

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
- **Picture in Picture with subtitle display** (parcial) — PiP não é o modo de uso de TV de sala.
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
