# Execução [[proavplayer]] MVP — remux fMP4 + playlist m3u8 manual + KSProAVPlayer

**Data:** 2026-07-18 · **Branch:** `task/proavplayer` (worktree isolado, base `1b8b46f`) · **Status:** implementado + revisado (lane de review, 5 commits de correção), aguardando build/validação em device pelo dono (regra: agente não roda `swift build`/`xcodebuild`).

## Escopo entregue (rota MVP do spike, sem muxer `hls`)

O binário FFmpegKit 6.1.4 não tem muxer `hls` e não preserva Atmos no `dec3` ([context/roadmap/spike-ffmpegkit-614-resultado.md](../roadmap/spike-ffmpegkit-614-resultado.md)). O MVP implementa a alternativa validada pelo spike: **muxer `mp4` fragmentado existente + playlists m3u8 escritas manualmente em Swift**, com o encaixe pronto para o fork [[ffmpeg-8x]].

## Commits (todos na branch `task/proavplayer`)

| Commit | Conteúdo |
|---|---|
| `cb4b5d0` | `feat: add loopback http server for proav local hls` |
| `054b01c` | `feat: add hls playlist builders with dolby vision signaling table` |
| `b94c0b3` | `feat: add truehd/dts to flac transcoder for proav audio` |
| `9caf934` | `feat: add proav remux session managing fmp4 segments and playlists` |
| `9dac60b` | `feat: add fragmented fmp4 remux mode to meplayeritem` |
| `2fd513b` | `feat: add ksproavplayer engine composing avplayer over local hls` |
| `7e9c0be` | `fix: seed flac transcode timestamps from source pts` |
| `2eaa7a5` | `fix: skip proav trailer when muxer header was never written` (review: `av_write_trailer` após `avformat_write_header` falho é UB/crash — movenc já deinicializado) |
| `8145f67` | `refactor: drop redundant dovi side data copy in proav remux` (review: `avcodec_parameters_copy` do n6.1 já copia `coded_side_data` e o movenc n6.1 lê o DOVI conf de `codecpar->coded_side_data` — verificado no source das tags; `av_stream_add_side_data` é removido no FFmpeg 8.x e quebraria o bump do fork) |
| `fd2f6e8` | `fix: ignore stale remux callbacks after proav relaunch` (review: seek durante o open do launch anterior abortava via interrupt callback → `sourceDidFailed` do item velho derrubava o launch novo com fallback espúrio; `onReady` velho podia apontar o AVPlayer para diretório em purga — agora delegate destacado no restart/shutdown/fail + guard de identidade de sessão nos callbacks) |
| `a879a2e` | `fix: fail proav session when remux ends with no segments` (review: EOF sem segmento — ex.: seek no fim do arquivo — não disparava `onReady` nem `onFailure` → player pendurado; agora falha → fallback) |
| `87af9dc` | `fix: release flac transcoder contexts on abandoned init` (review: `deinit` idempotente + frees dos caminhos de falha via propriedade — sem vazamento nem dangling) |

## Arquivos

### Novos
- `Sources/KSPlayer/MEPlayer/KSProAVPlayer.swift` — terceiro engine. `@MainActor`, implementa `MediaPlayerProtocol` compondo um `KSAVPlayer` interno (criado eagerly, com `replace(url:)` para a URL local quando o remux fica pronto — mantém `view`/`pipController`/`playbackCoordinator` válidos desde o init, exigência do `KSPlayerLayer`). Orquestra: remux (via `MEPlayerItem` em modo remux-only) → servidor HTTP loopback → `master.m3u8`. Seek e troca de trilha de áudio = **relançamento do remux** com `options.startPlayTime` (equivale ao `-ss` antes do `-i`; `MEPlayerItem.readThread` já faz `avformat_seek_file` no open). Workspace em `Caches/KSPlayer-ProAV/<UUID>/launchN/`, purgado a cada init e no shutdown.
- `Sources/KSPlayer/MEPlayer/ProAVHTTPServer.swift` — protocolo `ProAVLocalServer` + `ProAVLoopbackHTTPServer` com `NWListener` (Network.framework) em `127.0.0.1:porta-aleatória`. GET/HEAD, HTTP Range (bounded/from/suffix), keep-alive, content-types m3u8/mp4. **Sem dependência externa** (regra e); trocar por FlyingFox/GCDWebServer no futuro = implementar `ProAVLocalServer` e apontar `KSProAVPlayer.serverFactory`.
- `Sources/KSPlayer/MEPlayer/ProAVPlaylist.swift` — `ProAVVideoSignaling` (tabela perfil DV→tags, derivada do `DOVIDecoderConfigurationRecord` que `FFmpegAssetTrack` já extrai): P5 e P8.1 → tag `dvh1`, `CODECS="dvh1.PP.LL"`, `VIDEO-RANGE=PQ`; P8.4 → tag `hvc1` + `SUPPLEMENTAL-CODECS="dvh1.08.LL/db4h"`, `VIDEO-RANGE=HLG`; **P7 e não-HEVC → init falha → fallback `KSMEPlayer`**. HEVC sem DV: `hvc1.2.4.L<level>.B0` com VIDEO-RANGE por `color_trc` (PQ/HLG/SDR). `ProAVAudioStrategy`: E-AC-3 → **`.copyAwaitingFFmpeg8AtmosDEC3`** (o TODO estrutural do Atmos — hoje comporta-se como copy puro), AC-3/AAC/FLAC/ALAC → copy, resto (TrueHD/DTS/…) → `.transcodeToFLAC`. Builders de `master.m3u8` (BANDWIDTH/CODECS/RESOLUTION/FRAME-RATE/VIDEO-RANGE/SUPPLEMENTAL-CODECS) e `media.m3u8` (fMP4, `EXT-X-MAP`, `PLAYLIST-TYPE:EVENT`, `ENDLIST` no EOF).
- `Sources/KSPlayer/MEPlayer/ProAVAudioTranscoder.swift` — a peça genuinamente nova (primeiro caminho de **encode** do fork): decoder FFmpeg → `swr` para S16/S32 packed → acumulação até `frame_size` do encoder → `flac` (presente no 6.1.4, `_ff_flac_encoder` confirmado no spike). **Channel layout preservado** via `av_channel_layout_copy` do codecpar de origem. pts em timebase `1/sample_rate`, semeado do primeiro frame decodificado (mantém A/V sync no relançamento por seek). `bits_per_raw_sample` 16/24. Drain completo (decoder + parcial + encoder) no EOF.
- `Sources/KSPlayer/MEPlayer/ProAVRemuxSession.swift` — dono do diretório da sessão: sink de bytes do muxer via `avio_alloc_context` custom write-only (`seekable=0`), corta os bytes em `init.mp4` + `segmentN.m4s` nos flushes de fragmento, escreve `master.m3u8`/`media.m3u8` (rewrite atômico), callbacks `onReady` (após `minimumSegmentsBeforeReady`, default 2)/`onFailure`. `NSLock` + fila de eventos disparados fora do lock.

### Modificado
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` — modo remux-only: `init(url:options:remuxSession:)` (param novo com default nil, API existente intacta). Com sessão ativa: `startProAVRemux` no open (muxer `mp4`, `movflags=+empty_moov+default_base_moof+frag_custom+skip_sidx`, `strict_std_compliance=-2` p/ dvcC+FLAC-em-MP4, `codec_tag` `dvh1`/`hvc1` da tabela — validado presente em `codec_mp4_tags` do n6.1, `-sn` implícito — só vídeo+1 áudio mapeados); o `dvcC` chega ao movenc via `avcodec_parameters_copy` (que no n6.1 já copia `coded_side_data`, incluindo `AV_PKT_DATA_DOVI_CONF` — o movenc n6.1 lê de `codecpar->coded_side_data`; a cópia manual via API deprecated foi removida na review); em `reading()` os packets vão só para o muxer (nada de decode/putPacket — sem backpressure de renderização), corte de fragmento com `av_write_frame(ctx, nil)`+`avio_flush` no primeiro keyframe após `targetSegmentDuration` (default 2 s); EOF → drain FLAC → trailer → `ENDLIST` (trailer/drain gated em `remuxHeaderWritten` — nunca após header falho). Caminho legado de `startRecord`/gravação 100% preservado.

## Decisões relevantes

1. **Um arquivo por segmento** (`init.mp4` + `segmentN.m4s`), não byterange — playlist simples e serving trivial.
2. **`av_write_frame` (não interleaved) no caminho ProAV** — corte de fragmento determinístico no keyframe; o input (um único arquivo) já vem intercalado do demuxer.
3. **Playlist EVENT sem sliding window** — segmentos não são apagados durante a sessão (disco ≤ tamanho do arquivo de origem; o workspace é purgado no shutdown/init). A janela deslizante (`delete_segments`) fica para depois do fork, junto com o muxer `hls` real.
4. **Fallback = 1 degrau interno** (qualquer falha → `delegate.finish(error)` → `KSPlayerLayer` troca para `KSOptions.secondPlayerType`/`KSMEPlayer`, mecanismo já existente). O degrau intermediário `playlist.m3u8` SDR direto fica para a fase pós-fork.
5. **`AVDisplayCriteria` sem rebaixar DV**: o engine seta `preferredDisplayCriteria` direto (espelho de `KSOptions.updateVideo`, mas preservando `.dolbyVision`) **antes** de entregar o `master.m3u8` ao `AVPlayer` — não mexi no `KSOptions.updateVideo` para não afetar o caminho MEPlayer.
6. **Sem novos tipos públicos além do necessário**: `KSProAVPlayer`, `ProAVLocalServer`/`ProAVLoopbackHTTPServer`, `ProAVRemuxSession(.Configuration)`; o resto é internal.

## Aguardando explicitamente o fork [[ffmpeg-8x]]

- **Atmos (E-AC-3 JOC)**: o `dec3` escrito pelo `movenc` 6.1 não carrega `flag_eac3_extension_type_a`/`complexity_index_type_a` — o áudio toca como DD+ 5.1 sem o logo. O TODO estrutural está em `ProAVAudioStrategy.copyAwaitingFFmpeg8AtmosDEC3` (case dedicado, hoje idêntico a copy): quando o `Package.swift` apontar para o fork n8.1.x, **nenhuma mudança de código é necessária nesta lane** — o `mov_write_eac3_tag` novo passa a escrever a extensão sozinho; basta renomear/absorver o case e validar o logo Atmos na TV.
- **Muxer `hls` real**: substituiria `ProAVRemuxSession` + corte manual por `hls_segment_type=fmp4`/`hls_time`/`delete_segments` (aí sim janela deslizante + seek mais barato). A playlist manual continua válida como fallback.
- **TrueHD/DTS→FLAC não é gated** — funciona já no 6.1.4.

## Legendas (ponto de integração documentado, não implementado)

O remux não mapeia trilhas de legenda (`-sn`) e `KSProAVPlayer.subtitleDataSouce` retorna `nil`. Integração futura: o próprio `MEPlayerItem` remux-only já demuxa o MKV original e popula `assetTracks` (incluindo legendas com `FFmpegAssetTrack.subtitle`); a fase 2 é rotear os packets de legenda para as `SyncPlayerItemTrack<SubtitleFrame>` (hoje o modo remux-only pula `putPacket` de propósito — cuidado com PGS acumulando RAM), expor via `EmbedDataSouce` e sincronizar o overlay pelo clock do `KSAVPlayer` interno (`Coordinator`/`subtitleModel` já consomem por tempo). Nada disso exige o fork.

## Como o dono valida

### 1. Build
```fish
cd /Users/joaoalves/Developer/StreamHub/Player
git worktree list   # task/proavplayer no scratchpad do agente; ou: git checkout task/proavplayer
swift build 2>&1 | head -50
```
Não rodei build (regra da lane). Riscos de compilação checados na review por precedente no próprio repo: assinatura de `avio_alloc_context` (espelhada de `MEPlayerItem.getContext`), `AV_PKT_FLAG_KEY` (usado em `Model.swift:207`), macros com shift tipo `AV_CODEC_FLAG_GLOBAL_HEADER` importam (precedente `AV_CODEC_FLAG_LOW_DELAY` em `AVFFmpegExtension.swift:100`), padrão `swr_convert`/`Array(tuple:)` idêntico a `Resample.swift:256`; `av_stream_add_side_data` deixou de ser usado (removido na review). Conformidade `MediaPlayerProtocol`/`MediaPlayback` conferida membro a membro contra `MediaPlayerProtocol.swift`.

### 2. Ativar o engine (no StreamHub ou no Demo)
```swift
KSOptions.firstPlayerType = KSProAVPlayer.self
KSOptions.secondPlayerType = KSMEPlayer.self
```
Ajustes opcionais: `KSProAVPlayer.segmentDuration` (default 2 s), `KSProAVPlayer.minimumSegmentsBeforeReady` (default 2). ATS: loopback é isento por default; se o `AVPlayer` recusar `http://127.0.0.1`, adicionar `NSAllowsLocalNetworking` no Info.plist do app.

### 3. Matriz de amostras ([[sample-library]], `context/samples/SAMPLES.md`)
| Amostra | Esperado no MVP (6.1.4) |
|---|---|
| MKV HEVC HDR10 + E-AC-3 | toca via master.m3u8, TV em HDR10 (`VIDEO-RANGE=PQ`), áudio DD+ **sem** logo Atmos (esperado até o fork) |
| MKV DV P8.1 | TV entra em modo Dolby Vision real (tag `dvh1` + `dvcC` copiado + display criteria sem rebaixo) — validação-chave do MVP |
| MKV DV P7 (remux BD) | sinalização recusada → fallback silencioso p/ `KSMEPlayer` |
| MKV TrueHD 7.1 / DTS-HD MA | FLAC lossless multicanal via AVPlayer, sem erro de channel layout — peça nova, validar A/V sync e canais no receiver |
| MKV anime + ASS | vídeo/áudio tocam; legenda ainda não renderiza (fase 2) |
| Seek / troca de áudio | relançamento do remux; retomada <3 s depende de [[precache-disco]] (aceite formal fica gated nele) |

### 4. Harness comportamental do spike (opcional, agora trivial)
O remux de validação do `dec3` que o spike deixou como opcional pode usar direto esta lane: tocar uma amostra E-AC-3 JOC via `KSProAVPlayer` e inspecionar o segmento inicial gerado em `Caches/KSPlayer-ProAV/<UUID>/launch1/init.mp4` (pegar do device/simulador):
```fish
ffprobe -v error -show_entries stream=codec_name -select_streams a init.mp4
mp4box -diso init.mp4 -out - | rg -A4 dec3   # expectativa 6.1.4: box SEM os bytes da extensão type_a
```
Repetir o mesmo comando com o fork 8.x instalado → os bytes devem aparecer (critério de aceite do [[ffmpeg-8x]]). Checagem do FLAC em runtime: `avcodec_find_encoder(AV_CODEC_ID_FLAC) != nil`.

### 5. Inspeção rápida do HLS gerado (sem device)
No macOS o mesmo pacote roda: instanciar `MEPlayerItem(url: mkvLocal, options: KSOptions(), remuxSession: ProAVRemuxSession(configuration: .init(directory: dir)))`, `prepareToPlay()`, aguardar EOF e conferir `master.m3u8`/`media.m3u8`/segmentos com `ffprobe`/`mediastreamvalidator`.

## Pendências conhecidas (além do fork)
- `currentPlaybackTime` pós-seek assume que o `AVPlayer` reporta tempo relativo ao início da playlist regenerada (offset somado pelo engine); confirmar no device — se o `AVPlayer` usar o `tfdt` absoluto, remover o `startOffset` da soma em `KSProAVPlayer`.
- `TARGETDURATION` recalculado a cada rewrite (GOPs longos podem exceder o alvo) — tecnicamente fora da letra da spec para EVENT; `mediastreamvalidator` vai apontar, players toleram.
- Purga de workspace no `init` remove sessões de outros players ativos (PiP simultâneo é o único cenário afetado).
- Overhead CPU/energia de sessão longa (remux contínuo + AVPlayer) segue não medido — risco herdado da pesquisa.
- Janela residual de fallback espúrio (pós-review): `sourceDidFailed` do launch antigo já **em voo** para a main thread no instante exato do restart ainda passa (métodos de `MEPlayerDelegate` não identificam o item emissor); a review fechou a janela dominante destacando o delegate antes do shutdown — fechar 100% exigiria um proxy de delegate por launch.
- `CODECS` do P8.1 sinaliza `dvh1.08.LL` + `VIDEO-RANGE=PQ` (força rota DV plena); a spec de authoring da Apple sugere alternativa base `hvc1` + `SUPPLEMENTAL-CODECS="…/db1p"` — se alguma amostra P8.1 recusar no device, testar essa variante na tabela de `ProAVVideoSignaling`.
- Áudio planar com >8 canais estouraria o `AVFrame.data` (8 planes) no transcoder (`extended_data` não lido) — não há amostra real no catálogo (TrueHD/DTS ≤ 8ch); registrar se aparecer.
