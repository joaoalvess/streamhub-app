# ROADMAP — Lumen (fork GPL do KSPlayer) para o StreamHub

**Objetivo:** levar este fork à paridade com o KSPlayer pago e com o Infuse **no que importa para o StreamHub** (app tvOS pessoal que toca streams HTTP de debrid — remuxes/WEB-DL 4K em MKV e anime com legendas ASS):

- **Qualidade:** Dolby Vision nativo via remux MKV→HLS local→AVPlayer, HDR10+ dinâmico, Atmos nativo, FFmpeg 8.x.
- **Usabilidade:** seek com preview, troca de stream sem delay, buffering/precache, legendas ASS/fontes embutidas perfeitas, aparência de legenda nativa do sistema.

Tudo fora desses dois pilares vai para o Icebox — pode ser promovido depois, mas não ocupa o caminho crítico agora.

**Contexto estrutural:** a migração aconteceu — o StreamHub toca playback pelo player nativo deste fork (rota nativa no `PlaybackCoordinator` com fallback para Infuse, `NativePlayerView`, `ProAVPlayer` como primeiro engine), consumindo o pacote via SPM remoto. O marco [[migracao-streamhub]] fechou, e com ele caiu o gate que segurava o benefício ao usuário das tasks de usabilidade. Em 2026-07-25 aconteceram dois lotes (ver ✅ Entregue): as quatro tasks do Agora e, na sequência, nove lacunas de paridade com o Infuse. O que restou deles — pacing e ciclo de vida das legendas no remux, motor MEPlayer, anel de seek para trás e prewarm — é o novo caminho crítico.

Cada task referencia seu doc de pesquisa em `context/roadmap/`. Referências de linha (`arquivo.swift:123`) são as da data da pesquisa — revalidar contra o código ao pegar a task.

---

## ✅ Entregue

### Lote paridade Infuse (2026-07-25)

Nove lacunas de paridade com o Infuse executadas em 4 lanes paralelas (branch `feat/paridade-infuse` nos dois repos, worktrees). Só uma delas era task do kanban ([[hdr10plus]]); as outras oito vieram de uma lista de lacunas montada fora do repo e nunca tiveram card. Relatório completo — commits, decisões, conflito de merge, o que ficou quebrado e como validar — em [context/exec/paridade-infuse-2026-07-25.md](context/exec/paridade-infuse-2026-07-25.md). **O pacote compila e 150 testes passam**; a suíte continua abortando no ponto herdado da base (bug do `lazy var timer` no `deinit` do `KSPlayerLayer`, cuja cura está no stash `bbdedeb`, não commitado).

- **[[hdr10plus]]** — **a estratégia A não era "validação sem código", como o card e a pesquisa afirmavam.** O tvOS só aplica tone mapping dinâmico se a playlist declarar `SUPPLEMENTAL-CODECS="hvc1…/cdm4"` (brand CTA-5001 definida pela Apple na WWDC 2024); sem isso o stream passa como HDR10 estático mesmo com o SEI intacto. Entregue: `ProAVHDR10PlusScanner` (walker de NAL + prefix SEI tipo 39 + payload T.35 `0xB5`/`0x003C`/`0x0001`/app id 4), fiação no `MEPlayerItem` (side data primeiro, scan de SEI como fallback), flag na `ProAVRemuxSession` e brand `cdm4` também nas compatible brands do `ftyp`. Gate `hvc1 + PQ + sem supplemental` exclui estruturalmente todo Dolby Vision. **Falta validar em TV que o tone mapping dinâmico acende** — o critério de aceite continua aberto.
- **Legendas embutidas no `ProAVPlayer`** — o remux passou a decodificar e rotear packets de legenda (texto e bitmap) e o player expõe um `subtitleDataSouce` próprio, com proxies estáveis por trackID e store não-destrutivo que sobrevive aos restarts. O gap era maior que o previsto: o early-return de `reading()` descartava **todos** os packets em modo remux. Ficou de fora: pacing do decode-ahead e ciclo de vida dos proxies na troca de URL → task 1 abaixo.
- **Seek dentro da janela remuxada** — alvo dentro de `[origem, origem + soma dos segmentos fechados]` vai direto para o AVPlayer interno, sem derrubar sessão nem recriar `MEPlayerItem`; fora da janela mantém o restart. Junto veio a correção do relógio: a origem reportada era o instante **pedido**, não o keyframe em que o demux aterrissa — erro de até um GOP que só ficou visível quando a legenda passou a ser consultada por esse relógio.
- **Troca de faixa de áudio sem derrubar a reprodução** — reusa o ciclo `pendingSourceSwitch` (mesma URL, outro `preferredAudioTrackID`) e o `KSAVPlayer` ganhou `resumeShift` para o item novo retomar na posição certa em vez de herdar o offset da timeline velha (defeito que também afetava a troca de URL entregue em [[zero-delay]]). **Defeito novo conhecido:** cancelar uma troca pendente não reverte o `preferredAudioTrackID`, então o próximo restart reabre na faixa cancelada — correção de 1 linha listada na preparação transversal do 🎯 Agora.
- **DV perfil 8.2** — novo case no `ProAVVideoSignaling` com `SUPPLEMENTAL-CODECS="dvh1.PP.LL/db2g"` e `VIDEO-RANGE=SDR`; a matriz DV inteira ganhou teste. A Apple **não** documenta `db2g` no appendix (só `db1p`/PQ e `db4h`/HLG); a brand veio do shaka-packager (`dovi_decoder_configuration_record.cc`, case 2). Pendência de hardware com risco: o `preferredDynamicRange = .dolbyVision` chaveia o painel para DV enquanto a playlist anuncia SDR.
- **Object type AAC real na playlist** — `mp4a.40.5` (HE) e `mp4a.40.29` (HE v2) derivados do `codecpar.profile`, em vez de `mp4a.40.2` fixo, que fazia o AVPlayer poder recusar a variante e derrubar o título inteiro para o `KSMEPlayer`.
- **Sample rate do transcode limitado a 48 kHz** — fontes 96 kHz deixam de produzir saída que o AVPlayer recusa. Exigiu um drain do `swr` em `finish()`, que nunca existiu porque até aqui não havia conversão real de taxa.
- **Fonte embutida na legenda ASS** — **nada a fazer: já estava correto desde `7c53d53`**, o enunciado descrevia código anterior. Entregues os testes que faltavam do tick de exibição (o `.font` do parser sobrevive, o global só preenche onde falta) e a correção do `docs/07`.
- **Fração de timestamp de legenda** — `String.parseDuration` passou a ler a fração pela contagem de dígitos. **A premissa original era falsa** (não existe erro de 0,9 s em ASS: o `Scanner` já consumia `37.73` inteiro); o defeito real era SRT com fração de 1-2 dígitos (`,18` valia 18 ms). Bug pré-existente **não** corrigido, achado no caminho: `VTTParse` entrega cue settings junto com o timestamp e `00:03.380 align:start` vira 202,8 s.
- **Backend de áudio do fallback** — `KSOptions.audioPlayerType = AudioRendererPlayer.self` no app (1 linha, `StreamHubApp.swift:22`), que é o que destrava saída >2 canais no `KSMEPlayer` (`outputNumberOfChannels` só para de clampar quando `isUseAudioRenderer && isSpatialAudioEnabled`). Não afeta o `ProAVPlayer`.

Validações manuais pendentes: as 14 linhas do checklist de hardware no relatório. As três de maior risco, porque não têm medição nenhuma: PGS embutido decodificando **na thread do remux** (encode PNG por cue, inline); sincronia da legenda ao retomar no meio do filme; e faixa 7.1 numa rota 5.1 com o backend novo. E uma pendência que **não** é de hardware: 23 dos 174 testes nunca executam até o stash `bbdedeb` voltar — entre eles os 5 que são a entrega inteira da lane de legendas.

### Execução do kanban Agora (2026-07-25)

As quatro tasks do Agora foram executadas em lote (branch `task/agora-kanban` nos dois repos, lanes paralelas em worktrees). Relatório completo — commits, decisões, o que ficou de fora e como validar — em [context/exec/agora-resultado-2026-07-25.md](context/exec/agora-resultado-2026-07-25.md).

- **[[atmos-dec3]]** — `movflags` com `+delay_moov` (+ `use_editlist=0` para não perder o rebase de timestamps), nova fronteira do `init.mp4` via box-walk ISOBMFF (`ProAVInitBoundaryScanner`), gate que só libera o `moov` depois de um packet AC-3/E-AC-3 com syncword válido, detecção de JOC por `codecpar.profile` e `CHANNELS="16/JOC"` no `#EXT-X-MEDIA`; case `copyAwaitingFFmpeg8AtmosDEC3` aposentado. **Descoberta que mudou o escopo:** o `movenc` 8.x recusa escrever o `dec3` antes de parsear packets E-AC-3 — sem o `delay_moov` o header já falhava. Nada ficou de fora.
- **[[dv-nativo]]** — a parte de passthrough (P5/P8.1) não exigiu **nenhuma linha**: as três condições do `movenc` para escrever `dvcC`/`dvvC` já estavam satisfeitas desde o [[proavplayer]] (muxer `mp4`, side data no codecpar de saída, `strict_std_compliance=-2`). A conversão P7→P8.1 foi entregue: `DOVIPacketRewriter` dropa o NAL 63 e converte o RPU (NAL 62) com o **Libdovi 3.3.2 já vendorizado** (mode 2), override do registro DOVI de saída, signaling `dvh1.08.LL`, gate `KSOptions.convertDolbyVisionProfile7`, e falha explícita (→ `KSMEPlayer`) se nenhuma RPU aparecer. **Descobertas:** a lib cuida sozinha de emulation prevention e CRC32 (o risco XL da pesquisa não se materializou) e perfil 8 gera box **`dvvC`**, não `dvcC` — a inspeção do aceite tem que procurar `dvvC`. Ficou de fora: P7 em MPEG-TS (extradata Annex-B, recusado por design).
- **[[zero-delay]]** (camadas 1-2, motor AVPlayer) — `switchSource`/`cancelSourceSwitch` no `MediaPlayerProtocol`, hot swap por `AVQueuePlayer.insert(_:after:)` no `KSAVPlayer`, launch de remux paralelo no `ProAVPlayer` (que de quebra fechou a pendência antiga de fallback espúrio do [[proavplayer]]), `KSPlayerLayer.switchSource` sem `stop()` e sem `.preparing`, opt-in `KSOptions.isSourceSwitchEnabled`; no app, `switchNativeSource` preservando o `id` da sessão, migração do registro de progresso e roteamento por `contentKey`. Ficaram de fora: camadas 3/4 e o prewarm especulativo → tasks 2 e 4 abaixo.
- **[[seek-ram]]** (camada 1) — seek para frente dentro da janela de packets já bufferizada é servido da RAM: decisão na read thread, drenagem por identidade na decode thread, commit só depois de as trilhas confirmarem, e qualquer falha degrada para o `avformat_seek_file` atual. `KSOptions.isMemorySeekEnabled` (default ligado). Ficou de fora: camada 2 (anel para trás) → task 3 abaixo.

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

- [[sample-library]] — biblioteca curada de amostras de teste. O que ainda falta e para quê: E-AC-3 JOC (WEB-DL) para validar [[atmos-dec3]]; DV P5 (`dvhe.05.06`), P8.1 e P7 MEL/FEL para validar [[dv-nativo]]; DV 8.2 (`dv_bl_signal_compatibility_id == 2`) e HDR10+ para validar a sinalização `db2g`/`cdm4` entregue no lote paridade Infuse; MKV com PGS e MKV de anime com muitas faixas ASS para a task 1 abaixo; TrueHD 7.1 Atmos para validar o transcode FLAC entregue. Catálogo com fonte pública, spec exata e comandos mediainfo/ffprobe em [context/samples/SAMPLES.md](context/samples/SAMPLES.md); placeholders `<preencher>` dependem do acervo do dono.
- **Seletor de fontes alcançável durante a reprodução** (novo, 2026-07-25) — o roteamento de troca de fonte no app está fiado e testado (`selectSource` → `switchNativeSource` por `contentKey`), mas o `SourcesModalView` vive numa subárvore com `.disabled(nativeSession != nil)`, então nenhum gesto abre o seletor com sessão nativa ativa. Enquanto não existir esse ponto de entrada (candidato: overlay do player, fora do `.disabled`), o aceite de [[zero-delay]] entregue e das tasks 2 e 4 abaixo **não é exercitável ponta a ponta**. Trabalho de UI no `streamhub-app`, não no player.
- **Rabo do lote paridade Infuse** (novo, 2026-07-25) — três correções pequenas e já diagnosticadas, listadas em [context/exec/paridade-infuse-2026-07-25.md](context/exec/paridade-infuse-2026-07-25.md): (a) `.abortPending` não reverte `preferredAudioTrackID`, então cancelar uma troca de áudio faz o próximo restart reabrir na faixa cancelada (1 linha, `ProAVPlayer.swift:493`); (b) 8 pontos de documentação **pública** do lumen contraditórios ou apontando para um arquivo que não existe (`Core/Utility.swift`); (c) `ROADMAP.md` público do lumen listando HDR10+ como futuro enquanto o `docs/README.md` já o declara entregue. E antes de qualquer suíte: reaplicar o stash `bbdedeb` do `lumen-player`, que destrava os 23 testes que hoje nunca executam.

### 1. [[legendas-remux-pacing]] Pacing e ciclo de vida das legendas embutidas no remux

- **Objetivo:** tornar seguras de usar as legendas embutidas entregues no lote paridade Infuse — hoje o decode de legenda em modo remux não tem pacing, roda **síncrono na thread que alimenta o muxer**, e o store da faixa selecionada nunca é podado.
- **Critério de aceite:** com uma faixa PGS selecionada num filme longo, o remux não engasga e a memória do processo estabiliza (Instruments → Allocations, `UIImage`/`CGImage` não crescendo monotonicamente); num MKV com 8 faixas ASS, só as faixas consumidas por um proxy decodificam (as demais não enfileiram nada, nem depois do primeiro restart); trocar de URL não deixa entrada fantasma no menu de legendas; legenda de texto desmarcada no menu para de decodificar; nenhuma regressão no `KSMEPlayer` (a troca de legenda de texto continua instantânea lá).
- **Arquivos-alvo:** `MEPlayerItem.swift` (gate de `decode()` por track de legenda em modo remux, `readThread`/`reading`; `codecDidChangeCapacity` retorna cedo quando há `remuxSession` — é onde falta backpressure); `MEPlayerItemTrack.swift` (`SyncPlayerItemTrack.putPacket` decodifica na thread do chamador — avaliar mover o decode de legenda para fora da thread do remux); `FFmpegAssetTrack.swift:271-277` (o setter de `isEnabled` força `AVDISCARD_DEFAULT` para legenda de texto **independentemente do valor** — é a causa raiz, e mexer nele muda o `KSMEPlayer`); `ProAVEmbeddedSubtitle.swift` (poda do store por janela de tempo; descarte de proxies na troca de URL); `KSSubtitle.swift` (`SubtitleModel` tira um snapshot único de `infos` em `readyToPlay+1s` e nunca reconsulta — é o que trava o conserto dos proxies fantasma).
- **Dificuldade:** M
- **Dependências:** legendas embutidas no remux **entregues** (lote paridade Infuse) — esta task é o que faltou delas. **Coordenação obrigatória com as tasks 2 e 3**: as três mexem em `MEPlayerItem.swift`/`MEPlayerItemTrack.swift` (threading frágil, docs/03; **não introduzir locks novos**). Por ser a menor das três, deve entrar primeiro e as outras rebasearem em cima. Incógnita não medida: custo real do encode PNG por cue de PGS na thread do remux — item 1 do checklist de hardware do relatório.
- **Pesquisa:** [context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md](context/roadmap/proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md) (seção de resultado do lote paridade Infuse) — **a seção de pacing/backpressure ainda não existe; escrever antes de executar** (regras 5 e 6).

### 2. [[zero-delay-meplayer]] Troca de stream sem delay no motor MEPlayer (camadas 3/4)

- **Objetivo:** estender o hot swap entregue no motor AVPlayer para o `KSMEPlayer` (segundo engine, FFmpeg/Metal) e fazer o handoff de áudio sem gap, para que a troca sem tela preta valha também quando o ProAVPlayer não cobre a fonte.
- **Critério de aceite:** com `isSourceSwitchEnabled` ligada e o `KSMEPlayer` como engine ativo, trocar de candidato preserva o frame atual e a posição até o novo pipeline ter primeiro frame decodificado e áudio pronto; o backend de áudio reconfigura formato em runtime sem clique nem silêncio; falha do candidato degrada para o `set(url:options:)` atual sem regressão.
- **Arquivos-alvo:** `KSMEPlayer.swift` (hoje herda o default frio de `MediaPlayerProtocol.switchSource`, ou seja, cai no cold path); `MEPlayerItem.swift` (duas instâncias vivas — auditar retain cycle do close e estáticos); backends de áudio (`AudioEnginePlayer`/`AudioUnitPlayer`, reconfiguração de formato); `KSPlayerLayer.swift` (contrato de coalescing/cancelamento já pronto, só consumir).
- **Dificuldade:** L
- **Dependências:** [[zero-delay]] camadas 1-2 **entregue** — o contrato `switchSource`/`cancelSourceSwitch`, o coalescing por generation e o cancelamento real no engine já existem e são reaproveitados. **Novidade do lote paridade Infuse:** o `KSAVPlayer.switchSource` ganhou uma sobrecarga interna com `resumeShift` (a pública passa `0`) — o equivalente no `KSMEPlayer` precisa resolver o mesmo problema de origem de timeline. Bloqueio de validação herdado: o seletor de fontes ainda não é alcançável durante a reprodução (preparação transversal acima). Coordenação obrigatória com as tasks 1 e 3 (as três mexem em `MEPlayerItem` — threading frágil, docs/03; **não introduzir locks novos**). Incógnita ainda não medida: limite de sessões VideoToolbox simultâneas no tvOS.
- **Pesquisa:** [context/roadmap/video-switching-with-zero-delay.md](context/roadmap/video-switching-with-zero-delay.md) (com a seção de resultado das camadas 1-2)

### 3. [[seek-ram-anel]] Anel de retenção para seek curto para trás (camada 2)

- **Objetivo:** reter packets já consumidos por trilha (janela por tempo + teto de bytes, alinhada a keyframe) para que seek curto **para trás** seja servido da RAM — a metade que a camada 1 entregue não cobre.
- **Critério de aceite:** seek de −10s dentro da janela retida não chama `avformat_seek_file` nem gera requisição de rede e entrega o frame certo em <200 ms; teto de RAM respeitado em remux 4K de 80-100 Mbps; anel invalidado em troca de fonte, troca de trilha e loop gapless; seek fora da janela cai no caminho de rede atual sem regressão.
- **Arquivos-alvo:** novo `MEPlayer/PacketSeekCache.swift` (ou extensão do `CircularBuffer`, que já ganhou `peekEdges`/`scan`/`drain(upTo:)`/`wakeup` internos na camada 1); `MEPlayerItemTrack.swift` (`fastSeek`/`performMemorySeek` já existem e são o ponto de extensão); `MEPlayerItem.swift` (`isMemorySeekEligible`/`canServeSeekFromMemory` hoje exigem seek para frente); `KSOptions.swift` (janela/teto de bytes, ao lado de `isMemorySeekEnabled`).
- **Dificuldade:** L
- **Dependências:** [[seek-ram]] camada 1 **entregue**. **Descoberta da camada 1 que muda o desenho:** a render thread também consome a fila de packets de vídeo (`dropNextPacket`/`dropGOPPacket`), então reter e drenar tem que ser **por identidade**, não por contagem — e sem locks novos (docs/03). Coordenação obrigatória com as tasks 1 e 2 (mesmo arquivo, mesmo threading). Sinergia com o scrub preview entregue: consultar o anel antes de abrir rede para thumbnail. **Novidade do lote paridade Infuse:** o `ProAVPlayer` passou a ter seek dentro da janela já remuxada — caminho independente deste anel (é o AVPlayer interno quem seeka), mas os dois competem pela mesma expectativa de "seek curto é instantâneo"; medir os dois lado a lado.
- **Pesquisa:** [context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md](context/roadmap/memory-cache-for-fast-seek-in-short-time-range.md) (com a seção de resultado da camada 1)

### 4. [[prewarm-candidatos]] Prewarm especulativo de candidatos de stream

- **Objetivo:** começar DNS/TCP/TLS — e, no caminho ProAV, o próprio remux — do candidato provável **antes** de o usuário escolher, para que a troca de fonte commite na hora em vez de esperar os primeiros segmentos.
- **Critério de aceite:** com o seletor de fontes aberto, o candidato em foco chega com conexão (e, no ProAV, `master.m3u8`) pronta antes da seleção, mensurável nas métricas `KSOptions.dnsStartTime`/`tcpStartTime` existentes; a troca commita sem a rebobinada de 1-5 s medida nas camadas 1-2 (parte dela era um bug de origem de timeline, corrigido no lote paridade Infuse pelo `resumeShift`; o que sobra é o clamp na borda da playlist nova quando o remux ainda não alcançou a posição — é isso que o prewarm ataca); sair do seletor cancela o prewarm sem deixar workspace órfão nem sessão de remux viva; com o prewarm desligado, comportamento atual intacto.
- **Arquivos-alvo:** `ProAVPlayer.swift` (`makeLaunch` já isola um launch por candidato — é o gancho pronto); `KSAVPlayer.swift` (candidato enfileirado no `AVQueuePlayer`); `KSOptions.swift` (teto de candidatos/janela); no app, `SourcesModalView`/`MediaWindowView` (informar qual candidato está em foco).
- **Dificuldade:** M
- **Dependências:** [[zero-delay]] camadas 1-2 **entregue** — o contrato de switch e o cancelamento real no engine são o pré-requisito, e o `startRemux` antecipado do ProAV já é meio caminho. Precisa do seletor de fontes alcançável durante a reprodução (preparação transversal acima). Incógnita: custo de RAM/CPU/VideoToolbox de manter um remux especulativo vivo no tvOS — o mesmo teto que a task 2 precisa medir.
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
