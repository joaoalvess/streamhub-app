# Execução do lote "paridade Infuse" — legendas no remux, seek na janela, troca de áudio, sinalização DV 8.2/AAC/HDR10+, backend de áudio

**Data:** 2026-07-25 · **Branches:** `lumen-player@feat/paridade-infuse` (base `main` = `5bb0615`, HEAD `8bf5d2d`) e `streamhub-app@feat/paridade-infuse` (base `7c250e5`, HEAD `ddff494`) · **Status:** 9 tasks implementadas em 4 lanes paralelas, revisadas, uma rodada de correção na lane `proavplayer`, integradas por `merge --no-ff`. O pacote **compila** (`swift build` limpo, zero warning novo) e **150 testes passam**; a suíte continua abortando no mesmo ponto herdado da base. **Nada foi pushado. Nada foi validado em hardware.**

Este lote não teve documento de plano commitado — as 9 tasks vieram de uma lista de lacunas de paridade com o Infuse, montada fora do repo. Os ids usados pelos agentes (`p0-legendas-remux`, `p1-seek-janela`, …) **não são ids do kanban**; só `p2-hdr10plus` corresponde a uma task do `ROADMAP.md` ([[hdr10plus]]).

## Antes de mexer em qualquer coisa: 3 fatos de ambiente

1. **A suíte de teste do `lumen-player` já estava quebrada no `main`.** `swift test` aborta (SIGABRT) em `SourceSwitchTest.testCoalescedSwitchRequestsShareTheCandidateResult` com `Cannot form weak reference to instance of class Lumen.KSPlayerLayer`. Causa raiz: em `Sources/Lumen/AVPlayer/KSPlayerLayer.swift` o `timer` é `private lazy var timer: Timer = .scheduledTimer(…) { [weak self] … }` e o `deinit` chama `timer.invalidate()` — se a layer morrer sem nunca ter chamado `play()`, o `invalidate` materializa o `lazy` **durante** a desalocação e o `[weak self]` tenta formar weak ref para objeto em dealloc. Não é regressão deste lote.
2. **A cura desse crash está no stash do dono, não commitada:** `stash@{0}` = commit durável **`bbdedeb10aa658b1b456ca72e5aaf000f8db58c6`** ("workflow-paridade-infuse-2026-07-25", 3 arquivos, +45/−39). Ele troca o `lazy var timer` por `private var timer: Timer?` criado sob demanda. **Use o SHA, não o índice `stash@{0}`.** Nenhuma lane encostou em `KSPlayerLayer.swift`, justamente para não colidir com ele. Enquanto o stash não voltar, **23 dos 174 testes nunca executam**.
3. **Os 4 worktrees das lanes ficaram em `/private/tmp/claude-501/.../scratchpad/wt/`**, que é volátil. As branches (`task/paridade-legendas`, `task/paridade-signaling`, `task/paridade-proavplayer` no lumen; `task/paridade-audio-renderer` no app) sobrevivem nos repos, mas o registro de worktree vira lixo assim que o tmp sumir. Antes de qualquer `git worktree add`, rode:

```fish
git -C ~/Developer/appletv/lumen-player worktree prune
git -C ~/Developer/appletv/streamhub-app worktree prune
```

---

## Forma do histórico

Quatro lanes em worktrees próprios, todas partindo do mesmo HEAD, integradas na `feat/paridade-infuse` por três merges no lumen e um no app:

| Lane | Repo | Branch | Merge |
|---|---|---|---|
| `legendas` | lumen | `task/paridade-legendas` | `cc46eb4 merge: subtitle font and timestamp fraction fixes` |
| `signaling` | lumen | `task/paridade-signaling` | `1e3c740 merge: dolby vision 8.2, aac profile and hdr10+ signaling` |
| `proavplayer` | lumen | `task/paridade-proavplayer` | `8bf5d2d merge: embedded subtitles, in-window seek and hot audio switch` |
| `app` | app | `task/paridade-audio-renderer` | `ddff494 merge: audio renderer backend selection` |

A `main` do `lumen-player` está **5 commits à frente do `origin/main`** (série de refactors de concorrência nunca pushada). A `feat/paridade-infuse` sai desse trabalho não publicado — não estranhe o `git log` divergindo do GitHub.

---

## Escopo entregue por lane

### Lane `signaling` — sinalização do remux (3 tasks)

**DV perfil 8.2** (`p2-dv-p82`): novo `case (8, 2)` no switch de `ProAVVideoSignaling` (`ProAVPlaylist.swift:39-45`) — `codecTag = "hvc1"`, `CODECS` com a string HEVC da base layer, `SUPPLEMENTAL-CODECS="dvh1.PP.LL/db2g"`, `VIDEO-RANGE=SDR`, `preferredDynamicRange = .dolbyVision`. A matriz DV inteira ganhou teste: `(5,*)`, `(8,1)`, `(8,2)`, `(8,4)`, `(7,*)` com e sem conversão, e `(8,3)` provando que a recusa continua.

**Object type AAC + sample rate** (`p2-aac-samplerate`): `ProAVAudioStrategy.aacCodecsAttribute(profile:)` deriva `mp4a.40.5` de `AV_PROFILE_AAC_HE` (4) e `mp4a.40.29` de `AV_PROFILE_AAC_HE_V2` (28), default `mp4a.40.2`; `ProAVAudioTranscoder.targetSampleRate(forSource:)` limita a saída do transcode a 48 kHz. Foi preciso acrescentar um **drain do `swr`** em `finish()` (`swr_convert` com `in=nil`/`in_count=0`), que não existia porque até aqui nunca havia conversão real de taxa.

**HDR10+** (`p2-hdr10plus`): `ProAVHDR10PlusScanner.swift` (novo) — walker de NALs length-prefixed que filtra prefix SEI (tipo 39), desfaz emulation prevention e casa payload type 4 / country `0xB5` / provider `0x003C` / oriented `0x0001` / app id 4 (constantes conferidas contra `itut35.c`/`itut35.h` do FFmpeg). `MEPlayerItem` arma o scan em `startProAVRemux` (side data do stream primeiro) e varre cada packet de vídeo em `writeProAVPacket` **antes** da lógica de corte, desarmando após `remuxMoovWritten`. A sessão ganhou `noteDynamicHDR10Plus()` e `completeInitSegmentLocked` aplica `signaling.addingDynamicHDR10Plus()`, que só age quando `codecTag == "hvc1" && videoRange == "PQ" && supplementalCodecs == nil` — gate que exclui **estruturalmente** todo Dolby Vision. Resultado: `SUPPLEMENTAL-CODECS="hvc1…/cdm4"` na master + brand `cdm4` nas compatible brands do `ftyp` do init segment.

### Lane `proavplayer` — paridade funcional do engine de remux (3 tasks)

**Legendas embutidas no ProAVPlayer** (`p0-legendas-remux`) — o gap era maior que o enunciado: em `reading()` o early-return `if size <= 0 || remuxSession != nil` descartava **todos** os packets no modo remux, então ligar `decode()` sozinho não resolveria nada. Agora, com `remuxSession`: `readThread` chama `decode()` só nas tracks `.subtitle` e `reading()` roteia packet de legenda para `assetTrack.subtitle?.putPacket`. Vídeo e áudio continuam idle. `ProAVPlayer.subtitleDataSouce` deixou de ser `nil` e devolve `self`; os `infos` são **proxies estáveis por trackID** (`ProAVEmbeddedSubtitle.swift`, novo) que rebindam ao item corrente a cada restart e drenam a fila para um **store persistente e não-destrutivo** antes de todo shutdown.

> Por que o store existe: `CircularBuffer.search` além de consumir os casados **salta o `headIndex` por cima dos anteriores não casados, descartando-os**. Com seek regressivo dentro da janela (task seguinte) a legenda do trecho re-assistido simplesmente não existiria mais. O store insere ordenado, deduplica por `(start, texto, presença de imagem)` e capa `end == .infinity` quando chega part posterior.

**Seek dentro da janela remuxada** (`p1-seek-janela`) — `ProAVRemuxSession.closedSegmentsDuration` (só segmentos **fechados**) + função pura `ProAVPlayer.seekRoute(target:startOffset:closedSegmentsDuration:)`. Alvo dentro da janela vai direto para `innerPlayer.seek`, sem derrubar sessão nem recriar `MEPlayerItem`; fora da janela mantém o `restart(at:)` de antes.

**Troca de faixa de áudio a quente** (`p1-audio-switch`) — reusa o ciclo `pendingSourceSwitch` (mesma URL, outro `preferredAudioTrackID`): prepara em paralelo, comuta só quando pronto. `select(track:)` decide por função pura `audioSwitchAction` entre `ignore` / `abortPending` / `hotSwitch` / `coldRestart` — reselecionar a faixa que já toca virou no-op (corrige um restart inútil pré-existente).

**Rodada de correção** (4 commits, depois da revisão):
- **Relógio das legendas** (`a366158`): `currentPlaybackTime` usava `startOffset` (o instante **pedido**), mas `avformat_seek_file(ctx, -1, Int64.min, ts, Int64.max, 0)` com min/max ilimitados degenera em `AVSEEK_FLAG_BACKWARD` e o demux aterrissa no **keyframe anterior**; com `use_editlist=0` o t=0 do HLS é esse keyframe. O erro era invisível enquanto só alimentava a barra de progresso; com legenda consultada por esse relógio virava dessincronia de até um GOP. A sessão passou a publicar `playlistStartSeconds` e o player usa `timelineOrigin = session?.playlistStartSeconds ?? startOffset` em `currentPlaybackTime`, `playableTime` e no roteamento de seek.
- **Posição na troca a quente** (`f54ca3d`): `KSAVPlayer.commitPendingSourceSwitch` transplantava `player.currentTime()` da timeline **velha** para o item **novo**, que tem outra origem. `switchSource` ganhou sobrecarga interna com `resumeShift` (a assinatura pública do `MediaPlayerProtocol` continua e passa `0`); o `ProAVPlayer` passa `timelineOrigin − candidateOrigin`.
- **Faixa lembrada** (`d01fdad`): o ramo `.hotSwitch` passou a gravar `preferredAudioTrackID`, para um restart em voo não reabrir na faixa antiga.
- **Lock de I/O** (`e770741`): `closedSegmentsDuration` saiu do `NSLock` que a thread de demux segura durante `FileHandle.proAVWrite`/`closeSegment`; virou escalar cacheado sob um `progressLock` próprio. Ordem sempre `lock → progressLock`.

### Lane `legendas` — fonte embutida e timing (2 tasks)

**`p1-fonte-embutida` já estava implementada.** O enunciado descrevia código anterior ao commit `7c53d53` (`feat: render subtitles with fonts embedded in the container`), que é ancestral de `main`. Em `5bb0615`, `KSSubtitle.swift:349-358` já faz `enumerateAttribute(.font)` preenchendo **só onde `value == nil`**, e `AssParse.fontScale(playResY:preferredSize:)` já é como `SubtitleModel.textFontSize` escala ASS sem carimbar por cima. A lane entregou o que faltava: **4 testes do tick** e a correção do `docs/07-legendas.md`, que ainda descrevia o comportamento antigo. Nenhuma linha de produção mudou aqui — e essa foi a decisão certa: mexer no tick seria refactor sem defeito.

**`p1-ass-timing`: a premissa do enunciado era falsa.** Não existe erro de 0,9 s em ASS. `Scanner.scanDouble()` com locale nulo engole `37.73` inteiro no campo de segundos, então `"0:12:37.73"` já devolvia **757.73**; o `/1000` só era alcançado no ramo da vírgula (SRT). O defeito **real** estava aí: no ramo da vírgula a fração era tratada como milésimos qualquer que fosse a largura (`00:12:37,18` → 757.018; `,1` → 757.001). `String.parseDuration()` (`Sources/Lumen/Core/FoundationExtend.swift:35`) passou a ler a fração pela **contagem de dígitos** (`scanCharacters(from: .decimalDigits)` / `pow(10, digits.count)`). Conferido contra 23 timestamps: só os dois casos errados mudam; os outros 21 ficam idênticos, incluindo `01:00:01,140` → 3601.14, que o `testSrt` pré-existente já ancorava.

### Lane `app` — backend de áudio (1 task)

Uma linha em `StreamHub/StreamHubApp.swift:22`, dentro de `init()`, logo abaixo de `firstPlayerType`/`secondPlayerType`:

```swift
KSOptions.audioPlayerType = AudioRendererPlayer.self
```

Efeito real, conferido no código: `KSOptions.outputNumberOfChannels` (`KSOptions.swift:569-600`) só deixa de clampar para `min(maximumOutputNumberOfChannels, channelCount)` no tvOS quando `isUseAudioRenderer && isSpatialAudioEnabled`, e `isUseAudioRenderer` é literalmente `KSOptions.audioPlayerType == AudioRendererPlayer.self`. A linha destrava esse ramo. Ordem confirmada: o único ponto do app que cria player é `KSVideoPlayerView(…)` em `StreamHub/Playback/NativePlayerView.swift:19`, dentro de `body` — sempre depois de `App.init()`.

**Escopo:** `audioPlayerType` só afeta o `KSMEPlayer`. O `ProAVPlayer` toca por `KSAVPlayer`/AVPlayer e não passa por esse backend. A mudança é exatamente o caminho de fallback, como pedido.

---

## Commits

### `lumen-player` — `feat/paridade-infuse`, 28 commits, base `5bb0615`, HEAD `8bf5d2d`

| Lane | Commit | Conteúdo |
|---|---|---|
| legendas | `7eb561f` | `test: cover the subtitle tick preserving the parsed font` |
| legendas | `f1aa8a3` | `test: cover the ass header font surviving the display tick` |
| legendas | `0447f26` | `fix: read the subtitle timestamp fraction by its digit count` — **único diff de produção da lane** |
| legendas | `636c99c` · `7611f79` · `84fc0a5` | docs 07: tick de fonte, pegadinha de `parseDuration`, fatores de escala ASS |
| signaling | `c44df30` | `feat: signal dolby vision profile 8.2 with the sdr base layer brand` |
| signaling | `08badc4` | `fix: signal the real aac object type in the multivariant playlist` |
| signaling | `d195d17` | `fix: cap the transcoded audio output at 48 khz` (inclui o drain do `swr`) |
| signaling | `d5c85fb` | `feat: detect dynamic hdr10+ metadata in the hevc bitstream` — `ProAVHDR10PlusScanner` |
| signaling | `669fd18` | `feat: signal dynamic hdr10+ with the cdm4 brand in the remux output` |
| signaling | `8b0697b` | `feat: scan the first remux window for dynamic hdr10+` — fiação no `MEPlayerItem` |
| signaling | `8f87a79` | `docs: describe the 8.2, aac and hdr10+ signaling of the remux` |
| proavplayer | `544a4ca` | `feat(remux): decode and route embedded subtitle packets while remuxing` |
| proavplayer | `88d004a` | `feat(remux): add a persistent store for the embedded subtitle parts` |
| proavplayer | `c5e5dd7` | `feat(remux): expose the embedded subtitle tracks of the remuxed source` |
| proavplayer | `571c5ff` | `feat(remux): expose the duration already closed by the remux session` |
| proavplayer | `cc28300` | `perf(remux): seek inside the remuxed window without rebuilding the session` |
| proavplayer | `583bec6` | `perf(remux): switch the audio track without tearing playback down` |
| proavplayer | `80ff6b3` · `b6cf203` | refactors sobre código da própria lane |
| proavplayer fix | `e770741` | `perf(remux): read the closed duration without taking the writer lock` |
| proavplayer fix | `a366158` | `fix(remux): anchor the reported clock to the instant the playlist starts at` |
| proavplayer fix | `f54ca3d` | `fix(remux): keep the playback position when the source switch commits` |
| proavplayer fix | `d01fdad` | `fix(remux): remember the audio track a hot switch is preparing` |
| merge | `cc46eb4` · `1e3c740` · `8bf5d2d` | os três merges `--no-ff` |

### `streamhub-app` — `feat/paridade-infuse`, base `7c250e5`, HEAD `ddff494`

| Commit | Conteúdo |
|---|---|
| `0504ab1` | `feat: select the sample buffer audio backend at launch` — 1 arquivo, +1/−0 |
| `ddff494` | `merge: audio renderer backend selection` |
| _(este)_ | `docs(lumen): registrar a execução do lote paridade infuse` — este relatório, o kanban e os docs de pesquisa |

Higiene conferida no diff e nas mensagens: nenhum trailer, nenhuma atribuição a IA, nenhuma menção a StreamHub/debrid/TorBox/AIOStreams no repo público, nenhum caminho absoluto da máquina.

---

## Arquivos

### `lumen-player` — 20 arquivos, +1623/−50

**Novos (código):** `Sources/Lumen/MEPlayer/ProAVEmbeddedSubtitle.swift` (+158), `Sources/Lumen/MEPlayer/ProAVHDR10PlusScanner.swift` (+139).

**Modificados (código):** `MEPlayer/MEPlayerItem.swift` (+43 — 32 linhas do signaling, 11 do proavplayer, regiões distintas), `MEPlayer/ProAVPlayer.swift` (+170), `MEPlayer/ProAVRemuxSession.swift` (+45 — 16 signaling, 29 proavplayer), `MEPlayer/ProAVPlaylist.swift` (+27), `MEPlayer/ProAVAudioTranscoder.swift` (+26), `AVPlayer/KSAVPlayer.swift` (+10), `Core/FoundationExtend.swift` (+11).

**Testes (todos XCTest, ver "divergências"):** novos `ProAVEmbeddedSubtitleTest.swift`, `ProAVHDR10PlusScannerTest.swift`, `ProAVAudioSwitchTest.swift`, `ProAVSeekRoutingTest.swift`, `ProAVAudioTranscoderTest.swift`, `ProAVRemuxSessionTest.swift`; ampliados `ProAVPlaylistTest.swift`, `SubtitleTest.swift`. **74 funções de teste novas.**

**Docs públicos tocados:** `docs/03-engine-meplayer-demux-e-pipeline.md`, `docs/07-legendas.md`, `docs/README.md`. **Não tocados:** `Package.swift`, `FFmpegKit/`, `Sources/Lumen/Metal/`, caminho de decode do `KSMEPlayer`, `KSPlayerLayer.swift`.

### `streamhub-app` — 1 arquivo, +1

`StreamHub/StreamHubApp.swift`. `project.pbxproj` intocado (pastas sincronizadas). Nenhum teste novo: o critério de aceite era "uma linha, nada mais" e o efeito é a atribuição de um global estático dentro de `App.init()` — não há superfície testável sem subir o app.

---

## Decisões que divergiram do enunciado

1. **XCTest, não Swift Testing** (as 3 lanes do lumen, independentemente). Os 15 arquivos de `Tests/LumenTests/` são 100% XCTest, não há `import Testing` no repo e o `Package.swift` está em swift-tools-version 5.9. Swift Testing é convenção do `streamhub-app`, não do framework. Migrar seria decisão separada, com aprovação.
2. **`p1-fonte-embutida` não gerou diff de produção.** O código já estava correto desde `7c53d53`. A lane entregou testes + correção de doc em vez de reimplementar.
3. **`p1-ass-timing` corrigiu outro defeito.** A premissa (erro de 0,9 s em ASS) foi refutada rodando o corpo da função isolado; o defeito real era fração SRT de 1-2 dígitos.
4. **Drain do `swr` em `finish()`** (`d195d17`) — o enunciado dizia explicitamente "a mudança de sample rate entra no mesmo `swr_alloc_set_opts2`, não num passo novo". Com conversão real de taxa o resampler passa a reter amostras que nunca eram flushadas. O passo é no-op quando `in_rate == out_rate` (o `swr` nem aloca resampler). **Ressalva de honestidade:** o relatório da lane disse "o fim de cada faixa 96k perderia alguns milissegundos" — a magnitude está errada, o atraso do filtro default a 48 kHz fica bem abaixo de 1 ms. O passo é correto e barato; o ganho é ordens de grandeza menor do que foi reportado.
5. **Brand `cdm4` no `ftyp`** (`669fd18`) — a incógnita do enunciado ("investigar se vale") foi investigada **e implementada**: a spec HDR10+ da AOM referenciando CTA-5001 diz que a brand "should be used in the ftyp box". Barato aqui porque o init segment chega inteiro como `Data` e o fMP4 usa `default_base_moof` + `skip_sidx` (sem offset absoluto). Falha de parse cai no init original.
6. **Proxies estáveis em vez de `FFmpegAssetTrack` cru** como `infos` de legenda. O `KSMEPlayer` expõe as tracks direto, mas o `SubtitleModel` tira um snapshot único em `readyToPlay+1s` e o `remuxItem` morre a cada restart — os infos ficariam apontando para item shutdownado, com `stream` pendurado.
7. **Guarda de seek por `innerPlayer.isReadyToPlay`, não `reportedReady`.** `reportedReady` continua `true` durante um restart em voo; com ele um seek podia ser roteado para um AVPlayer ainda não pronto e pendurar a completion do restart anterior.
8. **`resumeShift` encostou no `KSAVPlayer`**, que o plano deixara fora de escopo. Foi decisão consciente na rodada de correção: sem isso a troca de áudio não preserva posição. A sobrecarga é interna e o caminho público continua com `resumeShift: 0`, então nenhum caller existente muda de comportamento.
9. **Commit de docs na lane `signaling`** (`8f87a79`), fora do escopo estrito das 3 tasks: o próprio diff invalidou três afirmações em material **público** (docs/03 dizia que DV 8.2 era recusado e que o transcode preserva o sample rate; docs/README dizia que HDR10+ era só lido e jogado fora). Deixar stale seria alegação falsa no repo público.

---

## Merge: o único conflito e como foi resolvido

Três merges `--no-ff` no lumen, na ordem `legendas` → `signaling` → `proavplayer`. Os dois primeiros limpos.

**Conflito add/add em `Tests/LumenTests/ProAVRemuxSessionTest.swift`.** As lanes `signaling` e `proavplayer` criaram o mesmo caminho com a mesma classe `ProAVRemuxSessionTest`, conteúdo 100% disjunto (5 testes de sinalização HDR10+/DV com fixtures ISO-BMFF e `avio_write` real; 5 testes da janela de reprodução com `closedSegmentsDuration`/`playlistStartSeconds`).

Resolvido **compondo as duas suítes numa classe só**, com os 10 testes na íntegra. Três pontos:

- **`directory`**: os lados eram incompatíveis (`URL` não-opcional criado em `setUp` vs `URL?` criado dentro do helper). Ficou a versão do `signaling`, estritamente mais forte — diretório único por teste, sempre removido no `tearDown`. O helper do `proavplayer` foi adaptado para usar esse `directory` compartilhado.
- **`makeSession()`**: dois helpers homônimos com assinaturas diferentes. O do `proavplayer` virou **`makeWindowSession()`**. Overloads coexistiriam em Swift, mas um par `makeSession()` / `makeSession(signaling:dynamicHDR10Plus:)` com `Configuration` e signaling diferentes é armadilha de leitura. **É a única alteração do integrador ao código de uma lane** — mecânica, sem mudança de comportamento.
- **imports**: união (`CoreGraphics` + `Libavformat`).

Nenhum `--ours`/`--theirs` em lugar nenhum.

**Verificação pós-merge dos dois arquivos que ambas as lanes tocaram sem conflito textual:**
- `MEPlayerItem.swift`: união exata (32 + 11 = 43 linhas). Ordem preservada em `reading()` — `writeProAVPacket` (que contém `scanDynamicHDR10Plus`) roda **antes** do roteamento de legendas, então o packet que dispara o flush do primeiro fragmento continua sendo escaneado.
- `ProAVRemuxSession.swift`: união exata (16 + 29 = 45). Ordem de locks conferida: `noteDynamicHDR10Plus`/`completeInitSegmentLocked` usam `lock`; `beginTimelineLocked`/`completeCurrentSegmentLocked` pegam `progressLock` **enquanto seguram** `lock`; os getters pegam só `progressLock`. Sempre `lock → progressLock`, nunca o inverso.
- `ProAVVideoSignaling` ganhou `convertsDolbyVisionProfile7` **com default no init**, então os call sites de 5 argumentos do `proavplayer` continuam compilando.

---

## Build e teste — o que é herdado e o que é novo

`swift build` no `lumen-player@feat/paridade-infuse`: **"Build complete!", exit 0, zero erro de compilação.** Os hits de `error:` no log são eco de código-fonte (`finish error: Error?`, docstring `- error: error with playing`), não diagnósticos.

### Correção metodológica: a baseline de warnings estava errada

O `warnings.txt` de baseline (33 entradas) veio de um build **incremental** (102 tasks). Um build limpo do mesmo target executa **194 tasks e emite 98 warnings**. Comparar 33 contra um build incremental da branch daria ~65 "warnings novos" falsos, em arquivos que ninguém tocou (`MediaExport`, `MediaTypeExtend`, `AudioGraphPlayer`, `VideoToolboxDecode`, `Resample`, `ThumbnailController`…).

A medição foi refeita limpa dos dois lados: o commit `5bb0615` foi exportado com `git archive` para um diretório temporário (read-only, sem worktree, sem tocar o repo) e buildado do zero; a branch foi buildada após `swift package clean`. **194 tasks e 98 warnings dos dois lados.** O normalizador foi validado antes de usar: reproduz o `warnings.txt` original byte a byte a partir do log da baseline.

**Resultado: os dois conjuntos de 98 warnings são idênticos.** `comm -23` vazio, `comm -13` vazio. +1623/−50 em 20 arquivos, **zero warning novo e zero warning resolvido**. Os 98 herdados são o passivo pré-existente de StrictConcurrency/`Sendable` e APIs depreciadas do macOS 12. No target de teste os warnings continuam só em `KSAVPlayerTest.swift` (3) e `KSPlayerLayerTest.swift` (2) — os 6 arquivos de teste novos não emitiram nenhum.

### Testes: falha herdada, não regressão

`swift test` → exit 1, SIGABRT. **Ponto de morte idêntico ao da baseline**: `SourceSwitchTest.testCoalescedSwitchRequestsShareTheCandidateResult`, mesmo erro objc do `KSPlayerLayer` (ver "3 fatos de ambiente").

| | Baseline (`5bb0615`) | Branch (`8bf5d2d`) |
|---|---|---|
| Passaram | 81 | **150** |
| Falharam (assertion) | 0 | **0** |
| Abort em | `testCoalescedSwitchRequestsShareTheCandidateResult` | o mesmo |

Os 81 nomes da baseline foram comparados um a um contra os 150: **todos continuam lá e continuam passando. Nenhum teste que passava deixou de passar.** 69 testes novos executaram e passaram — `ProAVEmbeddedSubtitleTest` (15), `ProAVHDR10PlusScannerTest` (14), `ProAVAudioSwitchTest` (7), `ProAVSeekRoutingTest` (6), `ProAVAudioTranscoderTest` (5), `ProAVRemuxSessionTest` (11, a suíte composta no merge, íntegra) e 11 novos em `ProAVPlaylistTest`.

**O que fica sem verificação:** foram adicionadas **74** funções, **69 rodaram**. Os **5 testes novos de `SubtitleTest` (lane `legendas`) nunca executaram** — a suíte fica depois de `SourceSwitchTest` na ordem e o processo morre antes. Ou seja: **a lane cuja entrega inteira é "testes + doc" não teve um único teste executado.** Junto com eles ficam sem rodar `TVScrubberTuningTests` (6), `VideoPlayerControllerTest` (1), `VideoPlayerViewTest` (1) e os 5 restantes de `SourceSwitchTest` — **23 de 174**. Reaplicar o stash `bbdedeb` destrava esses 23.

### `streamhub-app`

Não compilado (regra do workspace: nada de `xcodebuild`). O símbolo foi conferido por leitura: `AudioRendererPlayer` é `public class` com `public required init()` (`AudioRendererPlayer.swift:11,55`), `AudioOutput` é `public protocol`, `audioPlayerType` está dentro de `public extension KSOptions` (`Model.swift:85`). Compila em teoria; a validação é no Xcode, pelo dono.

---

## O que ficou quebrado, aberto ou fora de escopo

### Defeito novo, introduzido por este lote

**`.abortPending` não desfaz o `preferredAudioTrackID`.** Em `ProAVPlayer.swift:492-493` o ramo `.abortPending` só chama `abortPendingSourceSwitch()`; o `.hotSwitch` logo abaixo (`:495`) grava `preferredAudioTrackID = track.trackID`. Sequência: tocando A → escolhe B (`preferredAudioTrackID = B`) → antes do commit volta para A (`.abortPending`, candidata morre, áudio continua A, **preferred continua B**) → qualquer `restart` posterior (seek fora da janela, recuperação de falha) reabre o remux **na faixa B**, que o usuário cancelou, sem nenhum sinal. Correção de uma linha: gravar `preferredAudioTrackID = track.trackID` também no `.abortPending` (é o alvo, que é a faixa corrente — inócuo). Verificado no código em 2026-07-25, ainda presente na `feat/paridade-infuse`.

### Efeitos colaterais novos, sem correção decidida

- **Troca de faixa de áudio com o vídeo pausado retoma a reprodução.** O commit da troca → `KSAVPlayer.updateStatus` → `delegate.readyToPlay` → `ProAVPlayer.readyToPlay` com `reportedReady == true` consome `pendingSeekCompletion` e, se `options.isSeekedAutoPlay`, chama `play()`.
- **Seek dentro da janela aborta uma troca de áudio pendente sem feedback.** `seek` chama `abortPendingSourceSwitch()` e vai direto para `innerPlayer.seek`. Como o flip otimista de `isEnabled` foi removido, o popover nunca chegou a marcar nada — a escolha evapora silenciosamente. Re-selecionar funciona.
- **O check do popover de áudio só muda no commit** (~2 s), não na seleção. É a verdade sobre o que está tocando, mas é mudança perceptível. Reintroduzir o flip otimista só no ramo `coldRestart` é possível — decisão de produto, não feita.
- **Faixa de legenda de texto não pode ser desligada.** O setter de `FFmpegAssetTrack.isEnabled` (`FFmpegAssetTrack.swift:271-277`) força `AVDISCARD_DEFAULT` para legenda não-bitmap **independentemente do valor**. Desmarcar no menu não desliga o decode. Paridade com o `KSMEPlayer`, não regressão.
- **Filas de legenda das faixas não selecionadas crescem sem pacing — a partir do primeiro restart.** `ProAVEmbeddedSubtitleInfo.bind()` escreve `track.isEnabled` para **todo** proxy; combinado com o setter acima, toda faixa de texto do container passa a decodificar e enfileirar, e só a selecionada é drenada. No **primeiro** launch isso não acontece (`createCodec` deixa tudo em `AVDISCARD_ALL` e ninguém escreve `isEnabled` até um proxy dar bind). Como `codecDidChangeCapacity` retorna cedo com `remuxSession != nil`, o read loop não tem pacing nenhum e percorre o arquivo em segundos.
- **Custo de PGS na thread do remux (o item mais caro, e ninguém mediu).** `assetTrack.subtitle` é um `SyncPlayerItemTrack`; `putPacket` decodifica **síncrono, na thread do chamador** — que em modo remux é a thread que alimenta `av_write_frame`. Para texto é barato; para PGS/VobSub é `VideoSwresample` PAL8→ARGB + `CGImage.combine` + **encode PNG por cue**, inline, na thread que produz os segmentos que o AVPlayer está consumindo. A lane mediu isso como problema de memória; o efeito sobre o **throughput do remux** não foi considerado por ninguém.
- **`ProAVSubtitlePartStore` da faixa selecionada nunca é podado.** Para PGS é o filme inteiro em `UIImage`/PNG residente.
- **Habilitar legenda bitmap no meio do filme** só produz frames a partir de onde o demux de remux já está (à frente do playback): há um vão sem legenda até o playback alcançar. Equivalente ao `isSeekImageSubtitle` do `KSMEPlayer`, impossível neste caminho. Um seek fora da janela resolve.
- **Proxies fantasma no menu após troca de URL.** `commitPendingSourceSwitch` reseta os stores mas `syncEmbeddedSubtitles` só faz bind/append, nunca remove. Não foi corrigido de propósito: o `SubtitleModel` tira um snapshot único de `infos` em `readyToPlay+1s` e continua segurando o objeto antigo em `selectedSubtitleInfo`, então descartar os proxies deixaria o menu com rótulo velho apontando para proxy removido. O conserto real é o `SubtitleModel` reconsultar `infos` na troca de fonte.
- **Resíduo no relógio das legendas (~80-125 ms), não zero.** `playlistStartSeconds` é gravado em `beginTimelineLocked`, chamado de `shouldCutSegment(at:)`, que só roda para packets com `AV_PKT_FLAG_KEY`, usando `pts ?? dts`. Mas **todo** packet é escrito no output, e a timeline do fMP4 é rebaseada a partir do **DTS do primeiro packet escrito** (`use_editlist=0`). Âncora = PTS do primeiro keyframe; origem real = DTS do primeiro packet — para HEVC com reordenação de B-frames difere pelo atraso de reordenação, ~2-3 frames. É ~10× melhor que o erro anterior (um GOP inteiro), mas não é zero. Se incomodar na TV, a correção é ancorar no timestamp do primeiro packet escrito.
- **DV 8.2: `VIDEO-RANGE=SDR` com `preferredDynamicRange = .dolbyVision`.** Esse `preferredDynamicRange` alimenta `AVDisplayCriteria` (`ProAVPlayer.swift:150`) e troca o modo de saída HDMI. Se o tvOS não reconhecer a brand `db2g`, ele ignora o `SUPPLEMENTAL-CODECS` e toca a base layer SDR — mas o painel já foi chaveado para DV. Resultado: EOTF errado sobre imagem SDR, sem sinal de erro e sem fallback (o remux teve sucesso). Trocar para `.sdr` é um diff de 1 linha em `ProAVPlaylist.swift:44`. **Não mexer sem a TV na frente.**
- **`AudioRendererPlayer` chama `setPreferredOutputNumberOfChannels` a cada buffer** (`AudioRendererPlayer.swift:138-141`), dentro do loop de `requestMediaDataWhenReady`. Código pré-existente do lumen, mas **alcançado pela primeira vez pela linha do app**: com faixa 7.1 numa rota que reporta 5.1, o set falha, o erro é engolido pelo `try?`, a comparação `!= channelCount` fica permanentemente verdadeira e vira uma chamada IPC bloqueante para o `mediaserverd` ~20×/s na fila que alimenta o renderer. O `AudioEnginePlayer` anterior chamava isso uma única vez, em `prepare`.

### Mudança de valor reportado (não é regressão, mas o app precisa saber)

`currentPlaybackTime` e `playableTime` do `ProAVPlayer` passaram de `startOffset + inner` para `playlistStartSeconds + inner`. O número que o `PlaybackProgressStore` persiste muda em até um GOP (fica mais correto). Se houver comparação entre posição salva antiga e nova, vai divergir um pouco.

### Documentação pública do `lumen-player` em contradição consigo mesma

As lanes editaram `docs/03`, `docs/07` e `docs/README` e deixaram o resto stale. **Nada disso foi corrigido** — era diff fora do escopo do merge, e a regra do workspace proíbe escrever nota interna no repo público, mas essas são afirmações técnicas erradas em material de produto. Todas verificadas por grep na branch mergeada:

| Onde | O que afirma | Estado |
|---|---|---|
| `docs/03:179` | "não existe seek dentro do HLS gerado… o mesmo vale para `select(track:)` de áudio" | falso nas duas metades |
| `docs/03:181` | "**Sem legendas embutidas**" | manchete falsa (o corpo, "não entram na playlist", segue certo) |
| `docs/03:125` | "…enquanto o `ProAVPlayer` já soma `startOffset` por cima" | agora soma `playlistStartSeconds` |
| `docs/02:141` | rebobinamento na troca de fonte | corrigido por `f54ca3d` |
| `docs/README:54` | mesma afirmação | idem |
| `docs/07:46` | "`KSAVPlayer` retorna `nil`" | já era falso antes (retorna `AVSubtitleDataSouce`, `KSAVPlayer.swift:393`); agora também ignora o `ProAVPlayer`, que retorna `self` |
| `docs/07:36,61,73,116,133,134` e `docs/02:132,163` | apontam para `Sources/Lumen/Core/Utility.swift` | **esse arquivo não existe** — `parseDuration` está em `FoundationExtend.swift`, `mergeSortBottomUp` em `StdlibExtend.swift`, `UIColor(assColor:)` em `UIColorExtend.swift`, `CGImage.combine` em `CoreGraphicsExtend.swift`, `URL.isSubtitle` em `MediaTypeExtend.swift` |
| `docs/README:56` × `ROADMAP.md:17-19` (públicos) | um declara HDR10+ entregue, o outro lista como futuro | contradição literal |

### Bugs pré-existentes achados e **não** corrigidos (fora de escopo)

- **`VTTParse.parsePart` entrega cue settings junto com o timestamp.** `KSParseProtocol.swift:394-398` faz `components(separatedBy: "-->")` e passa `" 00:03.380 align:start"` inteiro para `parseDuration`. O guard de hora (`split(separator: ":").count > 2`) conta o `align:start` e devolve **202,8 s em vez de 3,38 s** — a cue fica ~3 min na tela e mascara as seguintes. Só aparece no formato curto `mm:ss.mmm`; com hora explícita sai certo. Confirmado rodando as duas versões da função: idêntico antes e depois, a lane não piorou nem melhorou. Conserto certo: cortar as cue settings em `VTTParse.parsePart`, **não** relaxar a heurística do `split`.
- **`AssParse.canParse` pode entrar em loop infinito** com `[Script Info]` sem linha `Format:` — o `while scanner.scanString("Format:") == nil` (`KSParseProtocol.swift:58-66`) não checa `isAtEnd` e nenhum ramo avança o scanner no fim da string.
- **`SubtitleModel.addSubtitle(dataSouce:)`** (`KSSubtitle.swift:382-391`) faz `append(contentsOf:)` sem dedupe. Só não duplica o menu a cada restart porque `ProAVPlayer.readyToPlay` encaminha ao layer uma única vez, guardado por `reportedReady`. **Acidente feliz, não desenho** — qualquer mexida nesse guard duplica o menu.
- **`aacCodecsAttribute` cobre só HE v1/v2.** AAC-LD (22), ELD (38) e SSR (2) caem em `mp4a.40.2` enquanto o `esds` diz object type 23/39/3. Comportamento idêntico ao de hoje, sem regressão; se aparecer no acervo, estender o switch para `mp4a.40.23`/`mp4a.40.39`/`mp4a.40.3`.
- **`Resample.swift:400-401`** decide interleaved/commonFormat comparando tipos concretos hardcoded (`AudioRendererPlayer.self`/`AudioUnitPlayer.self`). Funciona, mas é frágil; `docs/05` já lista o refactor (mover a decisão para o protocolo `AudioOutput`).

### Explicitamente fora de escopo (não tocado)

Renditions de legenda/áudio no master HLS (troca nativa pelo AVPlayer); fontes externas de legenda e o registro delas no app; pacing/backpressure do read loop de remux; HE-AAC com SBR implícito (chega com `profile = LOW` e continua saindo `mp4a.40.2`); P7 em MPEG-TS; push, em qualquer dos dois repos.

---

## Como o dono valida

### 0. Build

O `StreamHub.xcodeproj` resolve o Lumen do **GitHub `main`**; como nada foi pushado, a parte de app **só compila abrindo `StreamHub.xcworkspace`** (que resolve `../lumen-player` do disco). O worktree da lane `app` não serve para abrir o Xcode: falta `Secrets.plist`, `StreamHub.xcworkspace/`, `references/`, `build/` (gitignorados).

Para o pacote isolado, no checkout principal do `lumen-player`, já em `feat/paridade-infuse`:

```fish
cd ~/Developer/appletv/lumen-player
swift build            # esperado: Build complete, 98 warnings herdados, 0 erro
swift test             # esperado: 150 passam, SIGABRT em SourceSwitchTest
```

**Antes de dar a suíte por validada, reaplique o stash** — é o que destrava os 23 testes que nunca rodam, incluindo os 5 da lane `legendas`:

```fish
git -C ~/Developer/appletv/lumen-player stash apply bbdedeb10aa658b1b456ca72e5aaf000f8db58c6
```

Ele toca `KSPlayerLayer.swift` + 2 testes. Nenhuma lane mexeu nesse arquivo, então **não deve haver conflito** — mas confira antes de commitar por cima.

### 1. Checklist de hardware, por ordem de risco

| # | O que verificar | Como reproduzir | O que observar / o que a execução já sabe |
|---|---|---|---|
| 1 | **PGS embutido travando o remux** (o item novo, sem medição nenhuma) | MKV HEVC longo com faixa PGS/VobSub embutida; selecionar a legenda bitmap; deixar rodar 15-20 min | A imagem engasga ou dá buffering periódico depois de alguns minutos? Aparece `ProAV remux can not av_write_frame` no log? A memória cresce monotonicamente (Instruments → Allocations, filtrar `UIImage`/`CGImage`)? **Vídeo engasgando + CPU saturada na thread `_read` = decode PNG inline. Só memória crescendo = o store não podado.** |
| 2 | **Sincronia da legenda no "continuar assistindo"** | Retomar um filme com legenda embutida em ~30:00 (**não do zero** — do zero o erro é 0 por construção) | A fala aparece antes ou depois do áudio? Se **antes** e constante, medir o desvio grosseiro numa fala longa: ~100 ms é o resíduo PTS-keyframe/DTS-primeiro-packet (esperado, documentado acima); **da ordem de segundos significa que o fix do relógio não pegou o caso** |
| 3 | **Bug da faixa de áudio não revertida** (defeito conhecido, deve reproduzir) | Tocando faixa A → escolher B → **antes de o áudio mudar**, escolher A de novo → seek para bem longe (fora da janela, ex. +30 min) | **Esperado hoje: a mídia volta tocando B.** Se voltar em A, o cenário não se reproduziu. É o `preferredAudioTrackID` não revertido no `.abortPending` |
| 4 | **Troca de áudio: salto e sentido** | Filme em 30:00, marcar a posição na barra, trocar faixa, ver onde reaparece | Esperado: rewind pequeno (latência do remux, aceito no enunciado). **Se saltar para a frente**, o clamp da playlist EVENT está mordendo. Testar também **com o vídeo pausado**: se a reprodução retomar sozinha, é o `isSeekedAutoPlay` |
| 5 | **Legendas: desligar e trocar** | Legenda de texto ativa → desmarcar no menu → depois alternar entre 3-4 faixas num MKV de anime, seguindo a memória | Esperado hoje: desmarcar **não** para o decode (some da tela porque o store deixa de ser consultado). A partir do **primeiro restart** todas as faixas de texto estão decodificando |
| 6 | **Seek dentro da janela** | Seek regressivo curto (−30 s) num trecho já remuxado; depois seek exatamente para a borda superior (fim do que já foi remuxado) | Instantâneo, sem tela preta, sem recriar sessão, **e a legenda do trecho re-assistido reaparece** (é o teste do store não-destrutivo). Se travar ou ficar em stall exatamente na borda, encolher `seekRoute` em um segmento é diff de 1 linha |
| 7 | **Seek fora da janela** | Seek para +30 min | Deve manter o comportamento antigo (restart) e voltar a tocar com a legenda certa |
| 8 | **DV 8.2 (`db2g`)** | MKV com `dv_profile == 8` e `dv_bl_signal_compatibility_id == 2` | O painel entra em modo Dolby Vision (indicador da TV/receiver) **e** a imagem tem contraste HDR correto? **Painel em DV + imagem lavada/esmagada = o tvOS ignorou a brand e está tocando a base SDR com EOTF de DV** → trocar `preferredDynamicRange` para `.sdr` no case `(8, 2)`, `ProAVPlaylist.swift:44` |
| 9 | **HDR10+ (`cdm4`)** | Título HDR10+ real numa TV que suporte | A TV indica HDR10+ e o tone mapping varia por cena? **Se a mídia parar de tocar**, a suspeita é a brand no `ftyp` — remover é diff de 3 linhas em `ProAVRemuxSession.swift`. Confirmar também que a SEI aparece dentro dos ~2 s da primeira janela (o fio side data → SEI → flag não tem teste, exige mídia real) |
| 10 | **AAC 96 kHz e HE-AAC** | Título com trilha AAC 96 kHz (transcode) e outro com HE-AAC | Áudio sai a 48 kHz sem clique nem corte no fim das faixas (é o drain do `swr`); a variante não é recusada pelo AVPlayer por `CODECS` divergente do `esds` |
| 11 | **Áudio multicanal no fallback** (a linha do app) | Conteúdo que **não** passa pelo ProAVPlayer (AV1, VP9, VC-1, MPEG-2, H.264 High10) com faixa 5.1/7.1, em **Apple TV real** (não simulador) ligada a receiver | Log: `[audio] outputNumberOfChannels: … output channelCount: N` — `N` deve bater com a faixa, com `isUseAudioRenderer: true` e `isSpatialAudioEnabled: true`. **Caso específico: faixa 7.1 numa rota 5.1** — engasgo de áudio aqui é o `setPreferredOutputNumberOfChannels` disparando a cada buffer sem convergir |
| 12 | **Regressão de áudio no caminho comum** | Estéreo no `KSMEPlayer`; seek e troca de faixa durante a reprodução | Sincronia A/V com o clock vindo do `addPeriodicTimeObserver` de 10 ms (em vez do post-render notify do `AVAudioEngine`); volume/mute; velocidade de reprodução; flush do `AVSampleBufferAudioRenderer` no seek e na troca |
| 13 | **Legendas ASS/SRT: fonte e timing** | MKV com fontes como attachment + um `.srt` externo com fração de 1-2 dígitos | A legenda ASS renderiza com a fonte do container (o teste unitário prova só que o `.font` do parser sobrevive ao tick, não o registro CoreText); mudar o tamanho de legenda nas configurações continua surtindo efeito em SRT/VTT e em ASS (`AssParse.fontScale`, fotografado no `canParse` — ASS já parseado não reescala no meio do filme) |
| 14 | **Sanity check de não-regressão** | Dolby Vision + Atmos num título que já funcionava, **sem legenda selecionada** | Se isso quebrou, é o read loop |

---

## Pendências, em ordem de quem decide

**Correções de código já diagnosticadas, esperando só execução:**

1. `.abortPending` gravando `preferredAudioTrackID` (1 linha, `ProAVPlayer.swift:493`).
2. Os 8 pontos de documentação pública do `lumen-player` listados acima — inclusive as 8 referências a um arquivo que não existe. É material de vitrine de produto; compilador não pega.
3. `ROADMAP.md` público do lumen: mover HDR10+ para entregue com ressalva de validação, ou reescrever a entrada — hoje contradiz `docs/README.md:56`.

**Decisões de produto para o dono (não redesenhadas por conta própria):**

4. Flip otimista de `isEnabled` no popover de áudio: volta só no ramo `coldRestart`, ou o check continua refletindo só o que de fato toca?
5. `preferredDynamicRange` no DV 8.2 — depende de #8 do checklist.
6. Pacing/limite de decode-ahead de legenda em modo remux. A causa raiz é o setter de `FFmpegAssetTrack.isEnabled` forçar `AVDISCARD_DEFAULT` para legenda de texto — que é exatamente o que faz a troca de legenda ser instantânea no `KSMEPlayer`. Mexer nisso muda o comportamento do outro engine.
7. `SubtitleModel` reconsultar `infos` na troca de fonte (é o que fecha de verdade os proxies fantasma).

**Verificações que não foram feitas:**

8. **Nada foi validado em hardware.** Nenhum item da tabela acima.
9. **23 dos 174 testes nunca executaram**, incluindo os 5 que são a entrega inteira da lane `legendas`. Reaplicar `bbdedeb` primeiro.
10. **O `streamhub-app` não foi compilado.** Só leitura de símbolo.
11. **Nada foi pushado**, em nenhum dos dois repos.
