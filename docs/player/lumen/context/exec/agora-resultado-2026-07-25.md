# Execução do kanban 🎯 Agora — [[atmos-dec3]], [[zero-delay]], [[seek-ram]], [[dv-nativo]]

**Data:** 2026-07-25 · **Branches:** `lumen-player@task/agora-kanban` (base `main` = `ae68f21`) e `streamhub-app@task/agora-kanban` · **Status:** as quatro fases implementadas, revisadas adversarialmente (2-3 lentes por fase + 1 rodada sobre o resultado integrado) e corrigidas — **nada foi compilado, testado nem pushado**. Aguarda build no Xcode e validação em hardware pelo dono.

**Ressalva de honestidade sobre a revisão:** duas das lentes previstas — **concorrência/núcleo de playback sobre a F3** e **spec/crash-safety sobre o núcleo do reescritor Dolby Vision (F4)** — não chegaram a rodar na execução original: caíram por erro de conexão da API, não por decisão. Elas foram **refeitas depois**, sobre a branch final já merged, e produziram 8 commits de correção no `lumen-player`. O resultado está em "[Rodada extra: as duas lentes que tinham caído](#rodada-extra-as-duas-lentes-que-tinham-caído-2026-07-25)", no fim deste documento, e os commits estão na tabela abaixo.

Plano executado: [plano-agora-2026-07-25.md](plano-agora-2026-07-25.md). O plano previa fases sequenciais numa branch única; a execução real usou **worktrees paralelos** (ver "Forma do histórico").

## Forma do histórico (importante para ler o `git log`)

A F1 foi feita direto na `task/agora-kanban`. As três fases seguintes rodaram em paralelo, cada uma num worktree próprio com branch própria partindo de `main`, e foram integradas na `task/agora-kanban` por `merge --no-ff`:

| Lane | Branch | Merge |
|---|---|---|
| F2 [[zero-delay]] | `lane/f2-zero-delay` | `08ef7d9 merge source switching support` |
| F3 [[seek-ram]] | `lane/f3-seek-ram` | `23f22f4 merge in-memory forward seek path` |
| F4 [[dv-nativo]] (núcleo) | `lane/f4-rewriter` | `2fba523 merge dolby vision packet rewriter core` |

Os três merges auto-resolveram sem conflito (as regiões de `MEPlayerItem.swift` eram disjuntas: remux para F1/F4, seek para F3). Depois dos merges houve uma **rodada de revisão sobre o resultado integrado**, cujos fixes (`9f4095c`…`980ddf7`) estão no topo do log. Consequência prática: o log não é linear por fase — commits de uma mesma task aparecem antes e depois do seu merge.

---

## Escopo entregue por fase

### F1 — [[atmos-dec3]] Sinalização Atmos no remux

- `movflags` ganhou **`+delay_moov`** (o `moov` deixa de sair no `avformat_write_header` e passa a ser escrito no primeiro corte de fragmento, quando o `movenc` já parseou o header E-AC-3 e consegue escrever o `dec3` com a extensão type_a).
- **`use_editlist=0`** junto: sem ele, `+delay_moov` desligava silenciosamente o rebase de timestamps para zero do `movenc` e passava a escrever `edts`/`elst` no init segment — o `ProAVPlayer` soma `startOffset` por cima, então a posição dobraria depois de um seek.
- **Nova fronteira do `init.mp4`**: `ProAVInitBoundaryScanner.swift` (box-walk ISOBMFF com `largesize`, teto de 8 MB e falha explícita quando nenhum `moof` pode existir) + buffering em `ProAVRemuxSession` — o init segment agora é cortado no primeiro `moof`, não no `write_header`.
- **Gate de header parseado**: trilha AC-3/E-AC-3 só libera o primeiro flush depois de um packet que começa com o syncword `0x0B77`; se nenhum chegar, a sessão **falha explicitamente** (→ fallback `KSMEPlayer`) em vez de escrever um `moov` truncado.
- **Detecção de JOC** por `codecpar.profile == AV_PROFILE_EAC3_DDP_ATMOS` (30, conferido no header embarcado), com `CHANNELS="16/JOC"` na master playlist via `#EXT-X-MEDIA` + `AUDIO="main"`; `CHANNELS` é **omitido** quando a contagem de canais é desconhecida (em vez de emitir `"0"`).
- O case `copyAwaitingFFmpeg8AtmosDEC3` foi aposentado (era o TODO estrutural deixado pelo [[proavplayer]]).
- **Bug real encontrado no caminho**: `startProAVRemux` mapeava o stream de `preferredAudioTrackID`, mas `createCodec` deixava todos os streams em `AVDISCARD_ALL` menos o escolhido por `av_find_best_stream` — depois de uma troca de faixa de áudio, o stream mapeado nunca produzia packet. Corrigido (`f40adef`).

### F2 — [[zero-delay]] Troca de stream sem delay (MVP motor AVPlayer)

- `MediaPlayerProtocol` ganhou **`switchSource(url:options:completion:)`** e **`cancelSourceSwitch()`**, ambos com implementação default (o engine que não sabe fazer hot swap devolve `completion(false)` **sem efeito colateral**, e quem faz o restart frio é a `KSPlayerLayer`, único caminho que passa por `.preparing` e limpa o erro na UI).
- **`KSAVPlayer`**: candidato entra por `AVQueuePlayer.insert(_:after:)`, observação de `status` com timeout de 10 s, validação de faixa de vídeo tocável **antes** do `advanceToNextItem()`, `updateStatus` explícito no commit, troca de `urlAsset`/`cacheResourceLoader`/`options`, restauração da posição com `seek` pós-promoção, e todo o ciclo de vida do candidato serializado (`NSLock` + hop para a main).
- **`ProAVPlayer`**: `switchSource` não destrutivo — novo launch de remux em paralelo, sem derrubar servidor nem inner player; `ProAVLaunchDelegateProxy` por launch (**fecha a pendência antiga de fallback espúrio** do [[proavplayer]]); `applyDisplayCriteria` só quando o `preferredDynamicRange` muda (evita blank de HDMI mode switch em dub↔leg).
- **`KSPlayerLayer.switchSource`**: commita a URL sem `stop()` e sem `.preparing`, coalescing por generation (com as completions acumuladas e resolvidas), cancelamento real no engine, e degradação para `set(url:options:)` em falha.
- **`KSOptions.isSourceSwitchEnabled`** (instância, **default `false`**) roteia o `updateView`; `KSVideoPlayerView` espelha a URL do caller em `requestedURL` + `.task(id:)` para URL nova fluir sob a mesma identidade SwiftUI.
- **App**: `PlaybackCoordinator.switchNativeSource(videoURL:)` preserva o `id` da `NativePlaybackSession` (nenhuma regressão do fix `ea96318`), `PlaybackProgressStore.migrateSession(videoURL:to:)` move o registro de progresso para a chave da URL nova, `MediaWindowView.selectSource` roteia por **`contentKey`** (identidade de conteúdo — o predicado por título casava entre episódios diferentes da mesma série) e `NativePlayerView` liga `options.isSourceSwitchEnabled = true`.

### F3 — [[seek-ram]] Memory cache para seek rápido (camada 1)

- `CircularBuffer` ganhou `peekEdges()`, `scan(_:)`, `drain(upTo:)` (drenagem **por identidade**, numa única seção crítica — descarte por contagem corrompia a fila num flush concorrente) e `wakeup()`, todos `internal`, usando a `NSCondition` interna que já existia. Nenhum lock novo.
- `AsyncPlayerItemTrack` ganhou `fastSeek` + `performMemorySeek`: a decisão acontece na read thread, a **drenagem acontece na decode thread** (o consumidor), e o keyframe escolhido é confirmado por identidade antes do `doFlushCodec`.
- Fast-path no ramo `.seeking` do `readThread`, antes do `avformat_seek_file`, guardado por `!seekByBytes && opção && !isLoopModel && seek para frente && cobertura em todas as trilhas A/V assíncronas`. O commit (state, completion, clocks) **só acontece depois de as duas trilhas confirmarem o dreno** (deadline de 0,5 s); qualquer falha degrada para o caminho de rede atual com o completion handler intacto.
- `KSOptions.isMemorySeekEnabled` (instância + estática, **default `true`**). Logs de hit (`seek to … served from memory`) e miss (`memory seek miss`).
- No caminho de rede o flush das trilhas passou para **antes** do `avformat_seek_file` (antes, áudio/vídeo antigos continuavam tocando durante o bloqueio da rede/cache de disco).
- `docs/03-engine-meplayer-demux-e-pipeline.md` atualizado (§7).

### F4 — [[dv-nativo]] Dolby Vision nativo

**F4a (passthrough P5/P8.1) — zero linha de código.** O reconhecimento contra o source do FFmpeg n8.1.2 provou que as três (e únicas) condições do `movenc` para escrever `dvcC`/`dvvC` já estavam satisfeitas pelo código entregue no [[proavplayer]]: muxer `mp4` → `MODE_MP4`; `AV_PKT_DATA_DOVI_CONF` no `coded_side_data` do codecpar de **saída** (propagado por `avcodec_parameters_copy`); `strict_std_compliance = -2 ≤ FF_COMPLIANCE_UNOFFICIAL`. O `codec_tag` `dvh1` não influencia a decisão (mas está na tabela do muxer mp4). **F4a é validação de hardware, não código.**

**F4b (P7 → P8.1)** entregue:
- `DOVIPacketRewriter.swift` (novo): walker de NALs length-prefixed com bounds check em toda leitura, **drop do NAL type 63** (enhancement layer), **conversão do NAL type 62** (RPU) via `dovi_parse_unspec62_nalu` → `dovi_convert_rpu_with_mode(_, 2)` → `dovi_write_unspec62_nalu` do **Libdovi 3.3.2 já vendorizado**, prefixos de tamanho recalculados, e reescrita do `AVPacket` in place (o original fica intacto em qualquer erro).
- O buffer devolvido pelo Libdovi **já vem com o header `0x7C01`**, e a lib cuida do emulation prevention e do CRC32 — o risco que a pesquisa listava (reserializar bitstream à mão) não se materializou.
- Length size lido do byte 21 do `hvcC`; extradata Annex-B (MPEG-TS) → conversão recusada **antes** de a sessão começar → fallback `KSMEPlayer`.
- Override do `AV_PKT_DATA_DOVI_CONF` do codecpar de saída com o registro de 9 campos do FFmpeg 8 (`dv_profile=8`, `dv_bl_signal_compatibility_id=1`, `el_present_flag=0`, `dv_md_compression=0`; major/minor/level/rpu/bl preservados).
- `ProAVVideoSignaling` aceita `(7, _)` quando o gate está ligado, emitindo `dvh1` + `CODECS="dvh1.08.LL"` + `VIDEO-RANGE=PQ`; `KSOptions.convertDolbyVisionProfile7` (**default `true`**).
- **Guarda de honestidade**: se a conversão estiver ativa e nenhuma RPU tiver sido convertida até o primeiro corte de fragmento, a sessão falha (`ProAV dolby vision conversion found no rpu`) → fallback. Sem isso, um P7 dual-track (RPU numa trilha EL que o remux não mapeia) sairia anunciado como Dolby Vision 8.1 **sem metadata dinâmica nenhuma**.

---

## Commits

### `lumen-player` (branch `task/agora-kanban`, 66 commits, base `ae68f21`)

| Fase | Commit | Conteúdo |
|---|---|---|
| F1 | `7e3eabf` | `fix: delay the moov atom until audio parameters are parsed` — `+delay_moov`, `ProAVInitBoundaryScanner`, buffering na sessão |
| F1 | `d228d63` | `feat: signal dolby atmos audio in the hls master playlist` — `ProAVAudioSignaling`, `EXT-X-MEDIA`/`CHANNELS`, aposenta `copyAwaitingFFmpeg8AtmosDEC3` |
| F1 rev | `bcd1c72` | `fix: fail the remux when no init segment boundary can exist` — `size==0` vira `.malformed` + teto de 8 MB |
| F1 rev | `86ffe4c` | `fix: keep remuxed fragment timestamps zero based` — `use_editlist=0` |
| F1 rev | `0d23e09` | `fix: require a parsable audio header before the moov is flushed` — syncword `0x0B77`, retorno dos flushes checado |
| F1 rev | `f40adef` | `fix: let the demuxer deliver the audio stream the remux maps` |
| F1 rev | `a09a43c` | `fix: omit the channels attribute when the count is unknown` |
| F2 | `290848a` | `feat: add source switching to the media player contract` |
| F2 | `2c37b3e` | `feat: hot-swap sources on the avplayer engine via queue insertion` |
| F2 | `681543b` | `feat: switch proav sources with parallel remux launches` |
| F2 | `6fd3a5d` | `feat: opt-in hot swap when the video url changes` |
| F2 | `4d5182c` · `64a729b` | testes do contrato de switch |
| F2 rev | `9f3c758` | `fix: report unresolved source switches instead of faking a hot swap` |
| F2 rev | `e54fd2d` | `fix: reject unplayable candidates before promoting them` |
| F2 rev | `de10051` | `fix: drop the preferred audio track when the source url changes` |
| F2 rev | `b99c4f7` | `fix: cancel and coalesce pending source switches in the layer` |
| F2 rev | `40e1114` | `fix: follow the pending switch target and restart scrub previews` |
| F2 rev | `b07933d` | `test: cover cancellation and coalescing of source switches` |
| F3 | `d522320` | `feat: add non-destructive peek and bounded drain to the packet ring` |
| F3 | `0f891cb` | `feat: serve forward seeks from the buffered packet window` |
| F3 | `e3a629f` | `docs: describe the in-memory forward seek path` |
| F3 rev | `49d3ee1` | `refactor: keep the new ring helpers internal and assert on nil slots` |
| F3 rev | `3efd4c2` | `fix: drain the packet ring atomically by packet identity` |
| F3 rev | `59d725e` | `fix: reject the memory seek on packets without a timestamp` |
| F3 rev | `c64472a` | `fix: commit the memory seek under the lock that carries the fallback flag` |
| F3 rev | `7964d02` | `fix: flush the tracks up front when the memory seek is not eligible` |
| F3 rev | `b2ccf89` | `docs: document the memory seek option and the up-front track flush` |
| F4 | `5e649e3` · `2c21efc` | núcleo do `DOVIPacketRewriter` + testes do walker |
| F4 | `8a32f40` · `b52a180` · `a69d356` | menos cópias por packet, `hevcNALUnitLengthSize`, teste de ownership |
| F4 | `07874da` | `feat: add an option to convert dolby vision profile 7` |
| F4 | `f081497` | `feat: rewrite dolby vision profile 7 packets as profile 8.1 during remux` (fiação) |
| F4 | `fb81333` | `test: cover the converted profile 7 hls signaling` |
| F4 rev | `e264a79` | `fix: fall back when the converted stream carries no dolby vision rpu` |
| F4 rev | `7af05dd` · `309e178` · `cf02cf7` | packet sem payload, parar de reescrever após falha, remover sobrecarga morta |
| merge | `2fba523` · `23f22f4` · `08ef7d9` | merges das três lanes |
| int. rev | `9f4095c` | `fix: confirm the in-memory seek drain before reporting completion` |
| int. rev | `d90b0d7` | `fix: flush the tracks left out of the in-memory seek` (legendas) |
| int. rev | `332bc92` | `fix: serialize the pending source switch lifecycle` |
| int. rev | `b907717` | `fix: restore the playback position after promoting a switched source` |
| int. rev | `980ddf7` | `test: cover waking a consumer blocked on an empty queue` |
| docs | `69fab1a` · `4d9058d` | sinalização Atmos/DV do remux e quem drena a fila no seek em RAM (doc 03) |
| docs | `91b87be` | hot swap de fonte na camada AVPlayer (doc 02) |
| docs | `26c7068` | visão geral de capacidades depois do remux e do seek (doc 01 + `docs/README.md`) |
| docs | `f39a3f8` · `b7c6e8a` · `c550cef` | `README.md` e `ROADMAP.md` **públicos**: lista de features entregues, itens concluídos fora do roadmap, alegações de DV/Atmos aterradas no que o código faz |
| docs | `b197b25` · `58adf4b` · `0e85a90` | correções de precisão nos docs 02/03 (gate do remux, confirmação do dreno, ordem do coalescing) |
| F3 lente | `c57e557` | `fix: never resurrect a closed source from the memory seek commit` |
| F3 lente | `2e8eef4` | `fix: ignore memory seek drains from an abandoned attempt` |
| F3 lente | `e8b4ba2` | `fix: stop the old audio and video when the memory seek starts` |
| F3 lente | `b8082f9` | `fix: fail the memory seek fast when the decode thread cannot drain` |
| F4 lente | `f5dee32` | `fix: size the dolby vision record from the struct the demuxer publishes` |
| F4 lente | `320642d` | `fix: stop writing the remux output once the session failed` |
| F4 lente | `10963e7` | `refactor: name the unaddressable payload failure apart from the empty one` |
| F4 lente | `0873bd1` | `test: cover the libdovi conversion of bytes that are not an rpu` |

As linhas `docs` são o item 2 da F5 do plano (housekeeping de `README`/`ROADMAP`/`docs/`), feito nesta mesma branch. As linhas `F3 lente`/`F4 lente` são a rodada extra descrita no fim do documento.

Higiene conferida: todos os commits têm o dono como autor, **nenhum trailer**, nenhuma atribuição a IA, nenhuma menção a StreamHub/debrid/TorBox/AIOStreams nem caminho absoluto da máquina — no conteúdo e nas mensagens.

### `streamhub-app` (branch `task/agora-kanban`, 11 commits contando o que fecha este relatório)

| Commit | Conteúdo |
|---|---|
| `826b53b` | `feat: migrate playback sessions across source urls` — `PlaybackProgressStore.migrateSession` |
| `4997b06` | `feat: switch stream sources without restarting the native player` — `switchNativeSource`, roteamento no `selectSource`, flag ligada no `NativePlayerView` |
| `a5956c8` | `test: cover native source switching in the coordinator` |
| `4ce035d` | `fix: route source switches by content instead of title` — `contentKey` |
| `7d1eab5` | `test: cover the content key kept across a source switch` |
| `bf636f0` | `docs: add the agora kanban execution plan` — plano executado + apontamento no `ROADMAP.md` |
| `4847a08` | `docs: close the spurious proav fallback pendency` — pendência antiga do [[proavplayer]] fechada pela F2 |
| `93910c5` | `docs: report the agora kanban execution result` — este documento |
| `7d5d1a7` | `docs: retire the delivered agora tasks and reorder the lumen kanban` — 4 tasks entregues saem do 🎯 Agora, tasks novas entram |
| `0c75fe7` | `docs: record the two review lenses that were missing from the agora run` — seção da rodada extra |
| _(este)_ | `docs: correct the counts and the missing commits in the agora report` — números recontados contra o `git log` real |

---

## Arquivos

### `lumen-player` — novos
- `Sources/Lumen/MEPlayer/ProAVInitBoundaryScanner.swift` — box-walk ISOBMFF que separa `[ftyp][moov]` de `[moof][mdat]…` no stream do muxer.
- `Sources/Lumen/MEPlayer/DOVIPacketRewriter.swift` — walker/reassembler de NALs HEVC + conversão de RPU via Libdovi + builder do registro `dvcC`/`dvvC` de saída.
- `Tests/LumenTests/`: `ProAVInitBoundaryScannerTest.swift` (9), `ProAVPlaylistTest.swift` (13), `SourceSwitchTest.swift` (6), `MemorySeekTests.swift` (23), `DOVIPacketRewriterTest.swift` (17) — **68 testes XCTest novos, nenhum executado**. Os dois últimos do `DOVIPacketRewriterTest` são da rodada extra e são os únicos que exercitam o FFI real com o Libdovi.

### `lumen-player` — modificados
Código: `MEPlayerItem.swift` (remux: movflags, gate de header, fronteira do init, reescrita DOVI, override do side data; seek: fast-path em RAM), `MEPlayerItemTrack.swift`, `CircularBuffer.swift`, `ProAVPlaylist.swift`, `ProAVRemuxSession.swift`, `ProAVPlayer.swift`, `KSAVPlayer.swift`, `KSPlayerLayer.swift`, `KSVideoPlayer.swift`, `MediaPlayerProtocol.swift`, `KSVideoPlayerView.swift`, `KSOptions.swift`.

Documentação (housekeeping da F5, na mesma branch): `README.md`, `ROADMAP.md`, `docs/README.md`, `docs/01-vis-o-geral-e-build.md`, `docs/02-camada-avplayer.md`, `docs/03-engine-meplayer-demux-e-pipeline.md`.

Diff completo da branch (novos + modificados, código + docs): **25 arquivos, +2286/−113**.

**Não tocados** (regra): `Package.swift`, `FFmpegKit/`, `Sources/Lumen/Metal/`, caminho de decode do `KSMEPlayer`.

### `streamhub-app` — modificados
`StreamHub/Playback/PlaybackCoordinator.swift`, `StreamHub/Playback/PlaybackProgressStore.swift`, `StreamHub/Playback/NativePlayerView.swift`, `StreamHub/Features/MediaWindow/MediaWindowView.swift`, `StreamHubTests/NativePlaybackSessionTests.swift` (+4 testes Swift Testing). **Código: 5 arquivos, +87/−2**; documentação interna (plano, este relatório, `ROADMAP.md` do player e 4 arquivos de task): 8 arquivos, +724/−46. Diff completo da branch: **13 arquivos, +811/−48**. `project.pbxproj` intocado (pastas sincronizadas).

---

## Decisões relevantes

1. **`use_editlist=0` em vez de `avoid_negative_ts=make_zero`**: fixar `use_editlist` restaura o rebase para zero *e* suprime o `edts`/`elst` que o `+delay_moov` passaria a escrever — um flag em vez de dois efeitos.
2. **Falha explícita > estado novo**: trilha de áudio sem header parseável, `size==0` no box-walk, conversão P7 sem nenhuma RPU e extradata Annex-B derrubam a sessão ProAV e caem no `KSMEPlayer`, em vez de produzir um fMP4 que mente na sinalização.
3. **`completion(false)` para cold path**: o engine que não resolve a quente diz "não resolvi" e a `KSPlayerLayer` faz o restart frio pelo caminho normal. Isso preserva `.preparing`, que é o único ponto que limpa `playbackError`/spinner na UI.
4. **Coalescing por generation na layer, cancelamento real no engine**: `cancelSourceSwitch()` é requisito do protocolo (com default no-op), então `set(url:)`/`stop()` durante um swap matam o candidato de verdade.
5. **Roteamento de troca de fonte por `contentKey`, não por título**: sessão de episódio é criada com o título da *série*; o predicado por título casava entre episódios diferentes e migrava o progresso do episódio errado.
6. **Seek em RAM: decidir na read thread, drenar na decode thread**, com confirmação antes de reportar sucesso. A render thread também consome a fila de packets de vídeo (`dropNextPacket`/`dropGOPPacket`) — fato que o plano não previa — daí a drenagem por identidade.
7. **`DOVIPacketRewriter` opera sobre a ref (`outputPacket`), nunca sobre o `corePacket`** do pipeline; e monta os 9 bytes do registro DOVI à mão em vez de estender o struct público `DOVIDecoderConfigurationRecord`, que só tem 8 campos.
8. **Defaults escolhidos**: `isSourceSwitchEnabled = false` (opt-in, comportamento atual intacto), `isMemorySeekEnabled = true` e `convertDolbyVisionProfile7 = true` (ambos degradam para o caminho atual em qualquer falha).

---

## O que ficou explicitamente de fora

- **[[zero-delay]] camadas 3/4** — hot swap no motor `KSMEPlayer` (FFmpeg) e handoff de áudio sem gap. Hoje o `KSMEPlayer` herda o default frio do protocolo. Virou task nova no kanban.
- **[[seek-ram]] camada 2** — anel de retenção para trás. Virou task nova.
- **Prewarm especulativo de candidatos** no seletor de fontes (item 8 do design da F2). Virou task nova.
- **Ponto de entrada de UI para trocar de fonte durante a reprodução** — o roteamento no app está fiado e testado, mas o `SourcesModalView` vive numa subárvore com `.disabled(nativeSession != nil)` (`MediaWindowView.swift:87` dentro do `.disabled` de `:109`), então nenhum gesto abre o seletor com sessão nativa ativa. **Sem isso o aceite da F2 não é exercitável ponta a ponta.**
- **P7 vindo de MPEG-TS** (extradata Annex-B): recusado por design — nesse container os packets não são length-prefixed.
- **Legendas no remux ProAV** (pendência antiga do [[proavplayer]], fora do escopo deste plano).
- **Push**: nada foi enviado ao GitHub, em nenhum dos dois repos.

---

## Como o dono valida

### 0. Build (nada foi compilado)

O `StreamHub.xcodeproj` resolve o Lumen do **GitHub `main`**; como nada foi pushado, a parte de app da F2 **só compila abrindo `StreamHub.xcworkspace`** (que resolve `../lumen-player` do disco). Para o pacote isolado: `swift build` + `swift test` na `task/agora-kanban` do `lumen-player`.

Pontos que a análise estática não prova e o compilador vai julgar primeiro:
- `import Libdovi` a partir do target `Lumen` (é o primeiro binaryTarget não-produto importado dali; o mecanismo transitivo é o mesmo do `Libavcodec`). Se falhar: criar `FFmpegKit/Sources/FFmpegKit/include/dovi_shim.h` com `#import <Libdovi/rpu_parser.h>` e trocar por `import FFmpegKit` — **nunca** mexer no `Package.swift`.
- `import Libavcodec` nos targets de teste novos (`DOVIPacketRewriterTest`, `ProAVPlaylistTest`) — não há precedente de teste importando módulos do FFmpegKit neste repo.
- Warnings de `StrictConcurrency` nas closures armazenadas (`PendingMemorySeek`, completions coalescidas da layer).
- `MemoryLayout<AVDOVIDecoderConfigurationRecord>.size` em `MEPlayerItem.swift` (da rodada extra): o tipo vem de `libavutil/dovi_meta.h`, sob o `umbrella "."` do modulemap do `Libavutil`, e o arquivo já resolve símbolos de libavutil sem import explícito — deve resolver. Se o Xcode reclamar, o conserto é uma linha: `import Libavutil` no topo do arquivo.
- Os dois testes novos do `DOVIPacketRewriterTest` **executam FFI Rust de verdade** (parse → `get_error` → `rpu_free`). As entradas foram escolhidas para morrer em `validated_trimmed_data` do libdovi (comprimento < 25 e start bytes inválidos); trocá-las por uma RPU sintética "quase válida" reintroduz o risco de um panic do Rust atravessar a fronteira C.

### 1. Checklist de hardware

| Fase | Verificação | Como | O que a execução descobriu |
|---|---|---|---|
| F1 | Logo **Atmos** no receiver | amostra E-AC-3 JOC via ProAV | O `moov` agora só sai no 1º corte de fragmento. Se a trilha não entregar packet com syncword válido, a sessão **falha** e cai no `KSMEPlayer` (antes escrevia um `moov` truncado em silêncio) — se o fallback disparar, o log diz `ProAV audio track produced no parsable packet` |
| F1 | `dec3` com extensão type_a | `mp4box -diso init.mp4 \| rg -A4 dec3` sobre `Caches/Lumen-ProAV/<UUID>/launchN/` | inconclusivo no source: o muxer lê `complexity_index_type_a` do substream **independente** e o `codecpar.profile` vem do **último** header parseado (o dependente). Se divergirem em JOC real, a playlist pode anunciar `16/JOC` com um `dec3` sem o flag — **é isso que a inspeção precisa desempatar** |
| F1 | Sem regressão | AAC/AC-3/FLAC e TrueHD→FLAC tocando | E-AC-3 sem JOC sai com `CHANNELS="6"`; se a sondagem não fechar o layout, o atributo é **omitido** (não sai `"0"`). O primeiro `#EXT-X-MEDIA` sem `CHANNELS` é legal na RFC 8216, mas a Authoring Spec da Apple pede o atributo — observar se o AVFoundation aceita |
| F1 | Timestamps | seek num título ProAV e conferir a barra | `use_editlist=0` deve manter o `init.mp4` **sem `elst`** e os fragmentos rebaseados em zero, inclusive depois de um seek |
| F2 | Troca dub↔leg sem tela preta | abrir o **workspace**, ligar a reprodução nativa e trocar a fonte no seletor | **hoje não é exercitável**: com sessão nativa ativa o seletor está desabilitado (ver "ficou de fora"). O caminho do pacote pode ser exercitado num harness próprio; o do app precisa do ponto de entrada de UI |
| F2 | Fallback | `options.isSourceSwitchEnabled = false` | com a flag desligada o `updateView` roteia exatamente como antes |
| F2 | Posição preservada | trocar em ~40 min de reprodução | no caminho ProAV a reprodução **rebobina pela latência do remux** (1-5 s, ver pendências); no `KSAVPlayer` puro a posição é restaurada com `seek` logo após a promoção — pode haver um blip curto |
| F3 | Seek +10s/+30s sem rede | log: `seek to … served from memory`, **sem** `seek to … spend Time` | o log de hit só é emitido depois do commit irreversível, então um hit no log significa mesmo que a rede não foi tocada |
| F3 | Seek longo / para trás | log `memory seek miss` | agora áudio silencia e a imagem congela **no instante do comando** (o flush voltou a acontecer antes do `avformat_seek_file`) |
| F3 | Legendas após seek curto | seek de +20 s num MKV com legenda | as trilhas passivas passaram a ser flushadas no fast-path; observar se alguma legenda antiga reaparece |
| F4a | DV dinâmico real em P5 e P8.1 | lado a lado com Infuse; OSD da TV | **zero código novo** — é validação pura do que já existia |
| F4b | P7 MEL e FEL tocam como P8.1 | amostras P7; TV em modo DV; sem artefatos | a inspeção do init segment deve procurar **`dvvC`, não `dvcC`** (perfil 8 > 7 → o `movenc` escolhe `dvvC`). Se nenhuma RPU for encontrada, a sessão falha com `ProAV dolby vision conversion found no rpu` e cai no `KSMEPlayer` — sintoma esperado num P7 dual-track |
| F4b | Cor em FEL | comparar FEL convertido com a referência | foi usado o **mode 2** do `dovi_convert_rpu_with_mode` (curvas em no-op, padrão `dovi_tool -m 2`). Se houver desvio de cor, a alternativa é o **mode 4** (preserva luma/chroma mapping) — troca de uma constante |
| Pend. | Retorno do modo de vídeo ao sair | pendência antiga, re-observar | — |

---

## Pendências conhecidas

**Decisões de produto que ficaram para o dono (não redesenhei por conta própria):**

1. **Rebobinada na troca de fonte do ProAV** — `startOffset` é congelado no instante do pedido, mas o commit só acontece quando a nova sessão produz 2 segmentos; a fonte antiga continua avançando nesse intervalo, então a reprodução volta 1-5 s a cada troca. As duas saídas (margem preditiva no `startPlayTime`, que arrisca *pular* conteúdo; ou recomputar no commit e dar seek, que no ProAV significa reiniciar o remux) são trade-offs sem resposta única.
2. **Falha do ProAV no meio do título perde a posição** — o fallback recria o player com `secondPlayerType` usando as mesmas `options`, e `startPlayTime` vale 0 numa sessão sem seek. Vale para todos os gatilhos (inclusive os pré-existentes de FLAC/segmento). Propagar `currentPlaybackTime` para o fallback mexe em `ProAVPlayer`, arquivo tocado por várias lanes.
3. **Ponto de entrada de UI do seletor de fontes durante a reprodução** (ver "ficou de fora") — sem ele, o aceite da F2 fica no papel.

**Verificações que não foram feitas (entram como pendência, não como entrega):**

4. **Nada foi compilado nem executado.** Os 68 testes do player e os 4 do app foram **escritos**, nunca rodados.
5. **Assimetria do flag JOC entre substreams** (F1) — inconclusivo lendo só o source; precisa de amostra DD+ JOC real ou do texto da ETSI TS 103 420.
6. **`hvcC` com `array_completeness = 0` sob sample entry `dvh1`** — o `movenc` decide esse bit só por `tag == 'hvc1'`. É não-conformidade formal com a ISO 14496-15 e não é corrigível sem patchear o FFmpeg; impacto no AVFoundation é desconhecido.
7. **P7 com EL/RPU em trilha separada** nunca foi confrontado com amostra real — com a guarda nova, degrada para o `KSMEPlayer` em vez de publicar DV sem metadata.
8. **`memorySeekDrainTimeout = 0.5 s`** (F3) é uma constante nova sem validação em hardware: se o fallback de rede disparar em seeks que deveriam ser servidos da RAM, é o primeiro suspeito.
9. **Custo do `isMemorySeekEligible` na thread do chamador** — `peekEdges` + scan linear da fila por trilha, uma vez por seek, na main thread (~100 µs estimados). Se aparecer como hitch no transporte, cachear o candidato.
10. **Limite de sessões VideoToolbox** com dois pipelines vivos durante a janela do swap: só validável em hardware (risco listado no plano, janela minimizada pelo advance imediato).
11. **`options.videoFilters` acumula entre launches** do ProAV — pré-existente (já acontecia por `restart()`/`select(track:)`), inerte no caminho de remux porque item de remux não decodifica.
12. **Pendência antiga de `tfdt`/`startOffset` em playlist EVENT** ([proavplayer-mvp.md](proavplayer-mvp.md)) segue aberta e vale também para o launch do switch.

**Divergências entre o texto do plano e o resultado** (registradas, plano não editado nesses pontos):

13. O plano pedia tratar `size==0` no box-walk como "até o fim"; a implementação devolve `.malformed` **de propósito** — nesse stream um `size==0` só pode ser o placeholder de um `moov` truncado, e é o único guard que pega esse caso.
14. O plano dizia "CHANNELS presente sempre que houver trilha de áudio"; hoje é omitido quando a contagem é desconhecida.
15. O plano mandava "respeitar `isConvertNALSize`" na F4b; o reconhecimento provou que esse flag é exclusivo do decode VideoToolbox (a mutação `0xFE→0xFF` acontece numa cópia local do extradata). O texto do plano foi corrigido in loco; o length size vem do byte 21 do `hvcC`.
16. O plano dizia que a URL do `KSVideoPlayerView` deveria deixar de ser `@State`; falso — `openURL(_:)` a muta internamente. Corrigido in loco; a propagação virou `requestedURL` + `.task(id:)`.

**Housekeeping do lado do player:** feito e **coberto por este relatório** — `README.md`, `ROADMAP.md` público, `docs/README.md` e os docs 01/02/03 do `lumen-player` (item 2 da F5 do plano) estão na mesma `task/agora-kanban`, nos commits `69fab1a`..`0e85a90` da tabela acima. O que resta é a conferência do dono antes do push, com atenção à regra de material público: nenhuma alegação de feature no `README.md` deve ir além do que o código faz.

---

## Rodada extra: as duas lentes que tinham caído (2026-07-25)

Duas revisões adversariais previstas no plano não chegaram a rodar na execução original (erro de conexão da API): a lente de **concorrência + núcleo de playback sobre a F3** e a lente de **spec + crash-safety sobre o núcleo do reescritor Dolby Vision (F4)**. Elas rodaram depois, sobre o estado final da branch já merged, e a correção gerou 8 commits novos no `lumen-player` — as linhas `F3 lente`/`F4 lente` da tabela de commits acima, que fecham a branch em 66 commits.

| Achado | Veredito | Commit |
|---|---|---|
| Fast-path de seek podia ressuscitar `state` de `.closed` para `.reading` (checagem sem lock antes do commit) e travar o teardown para sempre — `readThread` nunca lê `readOperation.isCancelled` | procede | `fix: never resurrect a closed source from the memory seek commit` |
| Completion de uma tentativa de drenagem abandonada por timeout era creditado à tentativa seguinte, podendo confirmar um seek com uma track ainda não drenada | procede | `fix: ignore memory seek drains from an abandoned attempt` |
| No caminho elegível, A/V continuavam tocando o trecho pré-seek até a read thread destravar do `av_read_frame`, embora a barra já mostrasse o alvo | procede | `fix: stop the old audio and video when the memory seek starts` |
| Pedido de drenagem numa track cuja decode thread morreu (`.failed`/`.finished`) só era resolvido pelo timeout de 0,5 s | procede em parte — o `fastSeek` religa a thread quando a operação já terminou, então **não** era permanente; sobrava a janela entre o `break outerLoop` e o `isFinished` | `fix: fail the memory seek fast when the decode thread cannot drain` |
| Tamanho do `AVDOVIDecoderConfigurationRecord` fixo em 9 bytes, com o header dizendo que o `sizeof` não é ABI pública | procede | `fix: size the dolby vision record from the struct the demuxer publishes` |
| Depois de uma falha de conversão, a thread de leitura seguia chamando `writeProAVPacket`; `closeSegment` não tem guarda de falha e anunciava segmento truncado | procede | `fix: stop writing the remux output once the session failed` |
| `emptyRewrittenPayload` usado para duas causas sem relação | procede | `refactor: name the unaddressable payload failure apart from the empty one` |
| Nenhum teste exercitava `convertRPUNALUnitToProfile81` (superfície FFI com o libdovi) | procede | `test: cover the libdovi conversion of bytes that are not an rpu` |
| Ordem do commit do fast-path (`state` antes de `isSeek`/clocks) divergia do caminho de rede | procede | resolvido junto com o primeiro commit da tabela |

Detalhes que valem para a próxima leitura do código:

- O commit do fast-path agora acontece inteiro dentro da mesma seção crítica (`isSeek` → clocks → `state = .reading`), espelhando o caminho de rede. Ele sai do laço por `continue` — a condição do `while` já derruba a thread quando o estado é `.closed`.
- O caminho **de rede** (`avformat_seek_file`) tem a mesma forma antiga (checagem de `.closed` solta, escrita de `state` depois, fora do lock) e **não foi mexido**: o buraco é anterior a esta task e a correção pede mover a escrita do `state` para dentro do `condition`. Entra como pendência.
- A entrada do fast-path passou a exigir que a track esteja em `.decoding`/`.flush`; e todas as saídas da decode thread (mais o `shutdown`) resolvem o pedido de drenagem pendente com falha, em vez de deixá-lo apodrecer até o deadline.
- O reescritor de DV nunca mais é desligado no meio do caminho: a sessão falha e `writeProAVPacket` sai na primeira linha (`session.isFailed`), então nem packet cru nem `#EXTINF` novo saem depois da falha.
- O teste novo do libdovi usa entradas que morrem no `validated_trimmed_data` (comprimento < 25 e start bytes inválidos), justamente para não empurrar lixo pelo parser de bits.

**Pendências que esta rodada acrescenta:**

17. **Corrida de shutdown no caminho de rede do seek** (`MEPlayerItem.swift`, ramo do `avformat_seek_file`) — mesma classe do achado corrigido no fast-path, pré-existente à task: a checagem de `.closed` e a escrita de `state = .reading` não são atômicas, então um `shutdown()` no meio pode ressuscitar a read thread e bloquear o `closeOperation` (que depende do `readOperation`) para sempre.
18. **`startPacket(atOrBefore:)` varre o anel inteiro sob o lock** (`MEPlayerItemTrack.swift`), até 3× por seek (~1,5 k packets com 30 s bufferizados, ~100 µs por varredura com o lock retido). O corte antecipado exige uma margem sobre o alvo — os timestamps estão em ordem de decode e com B-frames o pts desordena — e mexer nisso sem poder medir em hardware não pareceu bom negócio. Fica como otimização anotada, não como bug. **Decisão do dono.**
19. **A `outputRenderQueue` de A/V passa a ser esvaziada duas vezes num seek elegível** (uma na thread do chamador, outra no `fastSeek`) — consequência do fix `e8b4ba2`. É idempotente e barato, mas é comportamento novo a observar em hardware: se o skip de +10 s passar a mostrar um frame congelado perceptível antes de retomar, o suspeito é a latência entre o pedido e o commit da read thread, não o flush em si.
