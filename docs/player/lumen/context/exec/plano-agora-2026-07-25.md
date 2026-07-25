# Plano de execução — kanban 🎯 Agora ([[atmos-dec3]], [[zero-delay]], [[seek-ram]], [[dv-nativo]])

**Data:** 2026-07-25 · **Base:** `lumen-player` @ `ae68f21` (main, em dia com origin) · **Modo:** execução por workflow multi-agente em sessão separada · **Status:** revisado adversarialmente (2ª varredura independente, ~30 refs conferidas; furos de design de F2/F3 corrigidos nesta versão) — aguardando execução

Este plano foi escrito após verificação do código atual (quatro varreduras independentes sobre o HEAD acima, incluindo `nm`/`strings` sobre os binários MPVKit) — todas as referências `arquivo:linha` abaixo são de 2026-07-25. Ainda assim, **revalide cada ref antes de editar** (regra 7 do ROADMAP).

---

## Regras invioláveis (do dono e do workspace)

1. **NUNCA rodar builds ou testes** — nada de `xcodebuild`, `swift build`, `swift test`, nem direto nem via subagente. Testes são **escritos, não executados**; o CI do repo (`.github/workflows/build.yml` roda `swift build` + `swift test -v`) valida quando o dono fizer push. O dono valida no Xcode dele.
2. **NUNCA fazer push.** Todo o trabalho fica em branch local `task/agora-kanban` criada a partir de `main`. O dono revisa, valida no hardware e faz push/merge.
3. **`lumen-player` é público.** Código, commits, testes e docs dele em inglês (docs 00-09 são PT-BR por decisão existente — atualizações neles seguem PT-BR). **ZERO menções** a StreamHub, debrid, TorBox, AIOStreams, caminhos absolutos da máquina ou notas de planejamento. Este arquivo de plano vive no `streamhub-app` e NÃO deve ser citado em nenhum commit/doc do `lumen-player`.
4. **Hook de segurança Swift**: edits em `.swift` são negados se contiverem force-unwrap `!`, segredo hardcoded, `.sync` na main thread ou `ObservableObject` sem `@MainActor`. Escrever `guard let`/`if let`/`??` sempre.
5. **Concorrência**: `lumen-player` usa `.enableExperimentalFeature("StrictConcurrency")`, **sem** default isolation. O núcleo MEPlayer tem disciplina **manual** de threads (`docs/03-engine-meplayer-demux-e-pipeline.md` §Pegadinhas): `state` sem lock tolera leituras stale de propósito; **não introduzir locks novos isolados** — usar as primitivas existentes (`NSCondition` do item, lock interno do `CircularBuffer`, `seekTimeLock` da track).
6. **Fronteiras da reescrita** (`lumen-player/docs/09-fronteiras-e-reescrita.md`): `MEPlayer/` e `Metal/` serão reescritos. F3 toca esse núcleo por ser exatamente a task do kanban — mas capacidade nova exposta para fora **entra por `MediaPlayerProtocol`** (regra 3 do doc 09), nunca como API pública nova de internals. `ProAV*` e `Cache/` são autoria própria e ficam.
7. **Testes**: XCTest em `Tests/LumenTests/` com `@testable import Lumen` (precedente: `M3UParseTest.swift`, `TVScrubberTuningTests.swift`). **Não** usar Swift Testing aqui (isso é convenção do app, não do player).
8. **Commits**: conventional commits em inglês minúsculo, vários pequenos, ordenados para que tipos referenciados existam antes do uso. **Sem `Co-Authored-By`, sem atribuição a IA** — só o título (corpo curto apenas se necessário).
9. **Sem dependência nova** no `Package.swift` — tudo que F4 precisa (Libdovi) já está vendorizado no FFmpegKit.
10. Dúvida real no meio do caminho → registrar em "Pendências" no relatório final, **não inventar**. Falha de fast-path deve sempre degradar para o comportamento atual, nunca para um estado novo.

---

## Incógnitas do kanban resolvidas (verificação de 2026-07-25)

Binários: MPVKit `0.41.0-n8.1.2` (FFmpeg n8.1.2, libavcodec 62.28), slice `tvos-arm64_arm64e`, verificados com `nm -gU` e `strings` sobre `.build/index-build/artifacts/ffmpegkit/`.

| Pergunta | Resposta | Evidência |
|---|---|---|
| bsf `dovi_rpu` existe? | **SIM** — mas só com opções `strip` (bool) e `compression` (none/limited/extended); **sem** opção de conversão de perfil | símbolo `_ff_dovi_rpu_bsf` em `dovi_rpu.o`; strings das AVOptions |
| bsf `dovi_split` existe? | **NÃO** | zero símbolos/strings |
| Rota P7→P8.1 | **`libdovi` 3.3.2 já vendorizado** como binaryTarget do FFmpegKit (`FFmpegKit/Package.swift:35,177-179`, `mpvkit/libdovi-build`), com a API C completa: `dovi_parse_unspec62_nalu`, `dovi_convert_rpu_with_mode`, `dovi_write_unspec62_nalu`, `dovi_rpu_remove_mapping` | `nm` sobre `Libdovi.xcframework/tvos-arm64_arm64e`; header `Headers/rpu_parser.h` |
| libavcodec linka libdovi? | NÃO (configure sem `--enable-libdovi`; só o Libplacebo consome) — a conversão tem que chamar o C API do Libdovi direto do Swift/shim | `nm -u` no Libavcodec |
| movenc escreve `dvcC`/`dvvC`? | **SIM** — `movenc.o` referencia `_ff_isom_put_dvcc_dvvc`; e `avcodec_parameters_copy` (usado em `MEPlayerItem.swift:324`) copia `coded_side_data` incluindo `AV_PKT_DATA_DOVI_CONF` | `nm -A` no Libavformat; docs do `codec_par.h` |
| `dec3` Atmos no movenc 8.x | fix presente (herdado do spike), **mas** ver risco novo de `+empty_moov` em F1 | strings do movenc no binário |

**Risco novo descoberto (muda o escopo de F1):** o binário contém as mensagens `"Cannot write moov atom before EAC3 packets parsed."` e `"...Set the delay_moov flag to fix this."` — o `mov_write_eac3_tag` do movenc exige packets E-AC-3 já parseados para escrever o `dec3`. O remux atual usa `movflags=+empty_moov` **sem** `+delay_moov` (`MEPlayerItem.swift:366`), ou seja, o `moov` sai no `avformat_write_header`, antes de qualquer packet. Consequência provável: **o header já falha hoje para trilhas E-AC-3/AC-3 em copy** (erro `.formatWriteHeader` → fallback silencioso para `KSMEPlayer`), e mesmo que não falhe, o `dec3` sai sem a extensão type_a. F1 inclui obrigatoriamente `+delay_moov` + reposicionamento da fronteira do `init.mp4`.

---

## Ordem, branch e conflitos

Branch única **`task/agora-kanban`** a partir de `main`, fases **sequenciais** (F1 → F2 → F3 → F4), commits agrupados por task (revert parcial fácil). Não paralelizar fases em worktrees: F1/F4 tocam a mesma região de `MEPlayerItem.swift` (remux) e F3 outra região do mesmo arquivo (seek) — sequencial elimina merge sem build.

Ordem escolhida (valor validável primeiro, risco por último):

| Fase | Task | Dificuldade | Arquivos-chave |
|---|---|---|---|
| F1 | [[atmos-dec3]] | S→M (subiu pelo delay_moov) | `ProAVPlaylist.swift`, `MEPlayerItem.swift` (remux), `ProAVRemuxSession.swift` |
| F2 | [[zero-delay]] MVP | M | `MediaPlayerProtocol.swift`, `KSAVPlayer.swift`, `ProAVPlayer.swift`, `KSPlayerLayer.swift`, `KSVideoPlayer.swift`, `KSVideoPlayerView.swift` + app |
| F3 | [[seek-ram]] camada 1 | S-M | `CircularBuffer.swift`, `MEPlayerItemTrack.swift`, `MEPlayerItem.swift` (seek), `KSOptions.swift` |
| F4 | [[dv-nativo]] P7→P8.1 | L | `DOVIPacketRewriter.swift` (novo), `ProAVPlaylist.swift`, `MEPlayerItem.swift` (remux), shim FFmpegKit |

F4 por último também porque F4a (passthrough P5/P8.1) é majoritariamente **validação de hardware** do que já existe — o código do passthrough está entregue desde o [[proavplayer]].

---

## F1 — [[atmos-dec3]] Sinalização Atmos no remux

**Objetivo:** o caminho ProAVPlayer declara Atmos de ponta a ponta — box `dec3` com `complexity_index_type_a` no fMP4 e `CHANNELS="16/JOC"` na playlist — para o receiver acender o logo Atmos.

**Aceite (kanban):** amostra E-AC-3 JOC remuxada acende Atmos no receiver; inspeção do `dec3` confirma o `complexity_index_type_a`; E-AC-3 sem JOC e demais codecs sem regressão.

### Estado atual (verificado)

- `ProAVAudioStrategy` (`ProAVPlaylist.swift:59-98`): case `copyAwaitingFFmpeg8AtmosDEC3` para `AV_CODEC_ID_EAC3` é **puramente documental** — `codecsAttribute`/`copiesBitstream` o tratam igual a `.copy`; nenhum consumidor distingue. Recebe só `codecId` (`MEPlayerItem.swift:333`), mas o `FFmpegAssetTrack` inteiro está disponível no call site.
- Playlist master (`ProAVPlaylist.swift:105-127`): variante única muxada, **sem `#EXT-X-MEDIA`, sem `CHANNELS`** (zero ocorrências em `Sources/`). Áudio só concatenado no `CODECS`.
- Remux (`MEPlayerItem.swift:299-380`, `startProAVRemux`): `movflags=+empty_moov+default_base_moof+frag_custom+skip_sidx` (`:366-369`); `session.finishInitSegment()` logo após o header (`:374-379`); corte de fragmento manual em `:401-413`; escrita de packet `:382-424`.
- Fronteira do init: `ProAVRemuxSession.finishInitSegment()` (`ProAVRemuxSession.swift:128-140`); IO custom com `seekable=0` (`:107-122`).
- Detecção de JOC: **inexistente**. Rota disponível sem parsing novo: o parser AC-3 do FFmpeg 8 popula `codecpar.profile` durante `avformat_find_stream_info` (`MEPlayerItem.swift:238`); o header embarcado define `AV_PROFILE_EAC3_DDP_ATMOS = 30` (e `AV_PROFILE_TRUEHD_ATMOS = 30`).

### Etapas

1. **Confirmar o comportamento do FFmpeg n8.1.2** por leitura do source (ex.: `curl` do raw na tag `n8.1.2`): (a) `mov_write_eac3_tag` com `empty_moov` sem packets → erro? (b) com `+delay_moov`, quando exatamente o `moov` é emitido no modo `frag_custom` (esperado: no primeiro flush de fragmento, com os parâmetros E-AC-3 já parseados); (c) o **parser** E-AC-3 (`ac3_parser`/decoder) seta `codecpar.profile = AV_PROFILE_EAC3_DDP_ATMOS` durante o `avformat_find_stream_info`? (a detecção de JOC da etapa 4 depende disso; se depender de probe fundo, um `options.probesize` baixo pode furar — nesse caso o fallback é `CHANNELS` numérico sem claim de Atmos, degradação aceitável). Registrar as três conclusões no relatório.
2. **`+delay_moov`**: acrescentar ao `movflags` (`MEPlayerItem.swift:366`). Sempre (um único caminho de código), não condicionado ao codec.
3. **Reposicionar a fronteira do `init.mp4` por box-walk**: com `delay_moov`, após o header só sai `ftyp` — o `moov` chega junto do primeiro `moof`+`mdat`. Nova regra em `ProAVRemuxSession`: o init segment é **tudo até o fim do box top-level que precede o primeiro `moof`**. Atenção a dois fatos do código atual: (a) a sessão **não acumula bytes** — `write()` despeja direto no `FileHandle` corrente (`ProAVRemuxSession.swift:294-306`), então o walker exige uma camada de buffering nova na sessão, com split no meio de um chunk; (b) `write()` retorna `size` **silenciosamente** quando `currentHandle == nil` (`:297`) — um erro de ordem entre walker e handles descartaria bytes sem falhar; o caminho novo deve falhar explicitamente nesse caso. O walker de boxes ISOBMFF: header de 8 bytes (size u32 + fourcc), tratar `size==1` (largesize u64) e `size==0` (até o fim), nunca force-unwrap; funciona igualmente com ou sem `delay_moov`. `finishInitSegment()` deixa de ser chamado no header (`MEPlayerItem.swift:378`, consumidor único — confirmado) e passa a ser disparado pela sessão ao detectar o primeiro `moof`; a master playlist, hoje escrita no `finishInitSegment` (`:135-136`), passa a sair nesse momento — `onReady` (gate de `minimumSegmentsBeforeReady = 2`) não é afetado.
4. **Detecção JOC + aposentar o case**: `ProAVAudioStrategy.make` passa a receber o track (ou o `codecpar`): E-AC-3 com `codecpar.profile == AV_PROFILE_EAC3_DDP_ATMOS` → `.copy` com `channels = "16/JOC"` (valor que a HLS Authoring Spec da Apple manda usar para Atmos); E-AC-3 sem o profile e AC-3 → `.copy` com `channels = "\(nb_channels)"`. O case `copyAwaitingFFmpeg8AtmosDEC3` é **removido** (absorvido por `.copy`) — os call sites do case estão todos em `ProAVPlaylist.swift` (`:61,67,83,92`); `MEPlayerItem.swift:333-355` só consome `.make`/`copiesBitstream` e ganha a passagem do track.
5. **Playlist**: introduzir um struct injetável (ex. `ProAVAudioSignaling { codecsAttribute, channels }`) para destravar teste unitário (o init de `ProAVVideoSignaling` exige `FFmpegAssetTrack` real — não repetir esse acoplamento no áudio). A master ganha uma rendition **muxada** (sem `URI` = o áudio está na própria variante):
   ```
   #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="main",NAME="Original",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="16/JOC"
   #EXT-X-STREAM-INF:BANDWIDTH=…,CODECS="dvh1.08.06,ec-3",…,AUDIO="main"
   ```
   `CHANNELS` presente sempre que houver trilha de áudio (JOC → `16/JOC`; senão contagem de canais).
6. **Testes (XCTest, string puro)**: master com EC-3 JOC (tem `EXT-X-MEDIA` + `CHANNELS="16/JOC"` + `AUDIO=`), EC-3 sem JOC (`CHANNELS="6"`), AAC, sem áudio (sem `EXT-X-MEDIA`); box-walk do init (Data sintética `ftyp+moov+moof+mdat`, incluindo box com largesize).

### Commits sugeridos

- `fix: delay the moov atom until audio parameters are parsed` (movflags + box-walk + fronteira do init + testes do walker)
- `feat: signal dolby atmos audio in the hls master playlist` (strategy + signaling + testes de playlist)

### Riscos

- Sequência de bytes do primeiro flush com `delay_moov` pode diferir do esperado (ex.: `avio_flush` intermediário) — o box-walk por estrutura (não por timing de callback) é a defesa; testar com Data fragmentada em chunks arbitrários.
- `TARGETDURATION`/duração do primeiro segmento muda de perfil com `delay_moov` — conferir que `minimumSegmentsBeforeReady` continua disparando `onReady`.

---

## F2 — [[zero-delay]] Troca de stream sem delay (MVP motor AVPlayer)

**Objetivo:** trocar de URL/candidato (dub↔leg, qualidade, fallback) sem tela preta/spinner — o frame atual só é solto quando o novo pipeline está pronto.

**Aceite (kanban, escopo MVP):** troca preservando `currentPlaybackTime` sem tela preta; camada 2 (`AVQueuePlayer.insert(_:after:)`) cobrindo o caminho HLS-remux→AVPlayer; métricas de abertura existentes usáveis para medir (no caminho ProAV o open do remux é FFmpeg → `dnsStartTime`/`tcpStartTime` já funcionam).

### Estado atual (verificado) — de onde vem a tela preta

1. `KSPlayerLayer.url.didSet` (`KSPlayerLayer.swift:128-157`): mesma engine + URL nova → `stop()` (`:316-328`, chama `player.shutdown()`) → `replace` → `prepareToPlay()`. `set(url:options:)` em `:259-264` só atribui `url`.
2. `KSAVPlayer.shutdown()` (`KSAVPlayer.swift:456-462`) faz `replaceCurrentItem(playerItem: nil)` → `AVPlayerLayer` sem item = preto. `replace(url:)` (`:465-473`) chama `shutdown()` incondicionalmente.
3. Overlay preto da UI tvOS: `KSVideoPlayerView.swift:140-147` + `:200-209` — `state == .preparing` levanta `Color.black + ProgressView` até `.readyToPlay`. Todo swap passa por `.preparing` hoje.
4. **A infraestrutura para hot-swap já existe estruturalmente**: o player concreto **já é `AVQueuePlayer`** (`KSAVPlayer.swift:14`, criado uma vez, `playerView` é `let` — player e layer sobrevivem à troca); o KVO de item é dirigido por `player.observe(\.currentItem)` (`:222-225`), então um swap via fila **re-liga os observers sozinho**. `insert(_:after:)`/`advanceToNextItem()` não são usados em lugar nenhum hoje.
5. ProAV: `attach()` (`ProAVPlayer.swift:105-110`) usa `innerPlayer.replace(url:)` (teardown); mas `restart()` (`:141-152`) **já mantém o servidor de pé** e as sessões são isoladas por `launchN` + guards de identidade (`self.session === session`, `:65,71`) — o servidor serve o workspace inteiro (`ProAVHTTPServer.swift:161-170`), então `launchN` e `launchN+1` já são servíveis simultaneamente pela mesma porta. **Cuidado**: `purgeWorkspaces()` no `init` (`:39,49-52`) destrói o workspace de outra instância viva — irrelevante para o MVP (uma instância só), mas bloqueia qualquer ideia futura de duas instâncias.
6. App: trocar fonte cria `NativePlaybackSession` **nova** (`id = UUID()`, `PlaybackCoordinator.swift:212-230`; overlay `if let` sem `.id()` em `MediaWindowView.swift:111-121`, `selectSource` em `:449-455`; `NativePlayerView.swift:12-25`). **Atenção**: como o overlay não é keyed por id e `NativePlayerView`/`KSVideoPlayerView` guardam estado em `@State`/`@StateObject`, o comportamento real da troca com sessão ativa (recria a view? URL nova chega ao player?) precisa ser **verificado no início da fase**, não assumido — é o mesmo pitfall de `@State` do item 5 do design. **Verificado na execução (2026-07-25, lado do pacote):** `NativePlayerView` usa o init público `KSVideoPlayerView(coordinator:url:options:title:onClose:)` com `url: URL` simples (`NativePlayerView.swift:19-25`), e esse init embrulha em `State(wrappedValue:)` (`KSVideoPlayerView.swift:70`) — logo, sob a mesma identidade SwiftUI a URL nova era de fato **descartada** antes do fix do item 5 (espelho `requestedURL` + `.task(id:)`); confirmando que o pitfall era real e que o app não precisa trocar de init. O único caller de `playerLayer.set(url:)` é `KSVideoPlayer.Coordinator.makeView` (`KSVideoPlayer.swift:162-190`), acionado por `updateView` quando a URL muda (`:66-71`).

### Design

1. **Contrato** (regra do doc 09): `MediaPlayerProtocol` ganha um requisito com implementação default:
   ```swift
   func switchSource(url: URL, options: KSOptions, completion: @escaping (Bool) -> Void)
   ```
   Default (extension) = caminho cold atual (`replace` + `prepareToPlay` + completion) — `KSMEPlayer` herda o fallback sem mudanças; a reescrita nasce sabendo do requisito.
2. **`KSAVPlayer.switchSource`**: criar `AVPlayerItem` do novo asset; `player.insert(item, after: player.currentItem)`; observar `status` do item candidato até `.readyToPlay` (timeout ~10s); então `advanceToNextItem()` e completion(true). Nunca `replaceCurrentItem(nil)`. Três obrigações no **commit** do swap (achados da revisão adversarial): (a) `statusObservation` é criado sem `.initial` (`KSAVPlayer.swift:354-357`) — um item já `.readyToPlay` ao ser promovido **não** redispara `updateStatus` (`:264-289`), deixando `mediaPlayerTracks`/`duration`/`naturalSize`/`embedSubtitleDataSouce` do item antigo (fatal justamente para dub↔leg): invocar o caminho de status explicitamente para o item promovido; (b) atualizar `urlAsset` e `cacheResourceLoader` (`:81-82,461,468`) para o asset novo (senão o próximo `shutdown` cancela o asset errado); (c) `isLoopPlay`/`AVPlayerLooper` ativo → cair direto no cold path. Candidato falhou/timeout → remover da fila + completion(false).
3. **`ProAVPlayer.switchSource`**: variante de `restart(at:)` **não destrutiva**: novo `startRemux(at: currentPlaybackTime)` com a URL nova **sem** `innerPlayer.shutdown()` e **sem** derrubar a sessão antiga; no `onReady` do launch novo → `innerPlayer.switchSource(masterURL)`; no completion(true) → `startOffset` atualizado, `requestCleanup()` da sessão antiga. **Correção sobre o kanban/versões anteriores deste plano:** os guards de identidade existentes cobrem só os closures da sessão (`ProAVPlayer.swift:65,71`) — os métodos de `MEPlayerDelegate` **não identificam o item emissor** (`sourceDidFailed` chama `fail()` sem guard, `:319-323`, e `fail()` derruba servidor + innerPlayer, `:126-139`). Como o design mantém o item antigo vivo e com delegate conectado durante o swap, é obrigatório o **proxy de delegate por launch** (classezinha que embrulha o delegate e só encaminha se `launch == atual` — a mesma solução que `context/exec/proavplayer-mvp.md` já apontou como pendência para fechar a janela residual de fallback espúrio; esta fase fecha as duas de uma vez). Sobre o `KSOptions` compartilhado entre item antigo e novo: `startPlayTime` só é lido no open (`MEPlayerItem.swift:580-588`), já consumido pelo item antigo — mutá-lo para o launch novo é seguro; as métricas (`dnsStartTime` etc.) terão corrida benigna de logging durante o swap (registrar no relatório, não "consertar").
4. **`KSPlayerLayer.switchSource(url:options:completion:)`**: NÃO chama `stop()`, NÃO seta `.preparing` (o estado corrente é mantido; o swap só transiciona quando o candidato commitar). A `url` armazenada **só é atualizada no commit do swap** (com flag interna para o `didSet` não disparar o caminho cold) — durante o swap em voo, `url` continua a antiga, para que o fallback de erro (`:442-448`, que recria `secondPlayerType` com `self.url`) e `nextPlayer`/`previousPlayer` (`:526-535`, dependem de `urls.firstIndex(of: url)`) continuem coerentes se o player atual falhar no meio. Novo `set(url:)`/`stop()` durante um swap → cancelar o candidato pendente primeiro (coalescing). Falha → degrada para `set(url:options:)` normal.
5. **UI do pacote — trabalho real (achado da revisão):** o overlay preto não é problema (só aparece em `.preparing`), mas o caminho de entrada é: `KSVideoPlayerView.url` é `@State public var` inicializada via `State(wrappedValue:)` (`KSVideoPlayerView.swift:40-47,70`) — **com a mesma identidade SwiftUI, uma URL nova passada no init nunca chega ao `updateView`** (o `@State` retém o valor antigo). **Correção verificada na execução (2026-07-25):** a URL **não pode** virar propriedade normal — `openURL(_:)` a muta internamente (`KSVideoPlayerView.swift:486-492`, alimentado pelo `onDrop` do macOS em `:342-347`). Solução implementada: manter o `@State` e espelhar a URL do caller numa propriedade `requestedURL` (capturada no init) + `.task(id: requestedURL)` no body que atualiza o `@State` quando o init recebe URL nova sob a mesma identidade — assim ela flui até `KSVideoPlayer.updateView` sem quebrar o `openURL`. Alternativa "app chama `playerLayer.switchSource` direto no coordinator" foi rejeitada: o guard de `updateView` (`KSVideoPlayer.swift:68`) compara `playerLayer.url != url` e **reverteria o swap** para a URL velha retida no `@State` no ciclo seguinte.
6. **Opt-in**: `KSOptions.isSourceSwitchEnabled` (instância, default `false` = zero regressão). `KSVideoPlayer.updateView` (`KSVideoPlayer.swift:66-71`): com a flag ligada e `playerLayer` existente → `playerLayer.switchSource` em vez de `makeView` cold.
7. **App (streamhub-app)**: manter a identidade da sessão na troca de fonte — `PlaybackCoordinator` ganha um caminho `switchNativeSource(...)` que atualiza a URL da `NativePlaybackSession` **preservando o `id`** (campo `var videoURL` ou sessão recriada com o mesmo id — decidir pelo menor diff); `MediaWindowView.selectSource` roteia por ele quando já há sessão nativa ativa do mesmo título; `NativePlayerView` repassa a URL nova ao `KSVideoPlayerView` (que, com o item 5 feito, a propaga ao `updateView`). **Não regredir o fix `ea96318`** (detached-check no dismantle do coordinator) — o switch não pode recriar o `Coordinator` nem marcar a view como detached.
8. **Prewarm (camada 1 do kanban)**: entregar o mínimo — o próprio `startRemux` antecipado do item 3 já é o prewarm real do caminho ProAV (DNS+TCP+probe do FFmpeg acontecem antes do commit). Prewarm especulativo de candidatos no seletor de fontes fica **fora do MVP** (registrar como extensão em Pendências).

### Testes

- Engine fake conformando `MediaPlayerProtocol` (precedente: `KSPlayerLayerTest.swift`) para: (a) default de `switchSource` cai no cold path; (b) `KSPlayerLayer.switchSource` não passa por `.preparing` e mantém o estado; (c) falha do candidato degrada para o caminho cold.

### Commits sugeridos

- `feat: add source switching to the media player contract`
- `feat: hot-swap sources on the avplayer engine via queue insertion`
- `feat: switch proav sources with parallel remux launches`
- `feat: opt-in hot swap when the video url changes` (KSVideoPlayer/KSOptions)
- No `streamhub-app`: `feat: switch stream sources without restarting the native player`

### Riscos

- **Limite de sessões VideoToolbox** com dois pipelines decodificando durante o swap (incógnita do kanban) — só validável no hardware; o design minimiza a janela (advance imediato no ready).
- Usuário troca de novo no meio do swap → coalescer: cancelar candidato pendente antes de criar outro.
- Playlist EVENT do launch novo começa do zero com `startOffset` somado — conferir a mesma pendência de `tfdt` já registrada no exec do proavplayer (`context/exec/proavplayer-mvp.md`, Pendências).

---

## F3 — [[seek-ram]] Memory cache para seek rápido (camada 1)

**Objetivo:** seek pra frente dentro da janela já bufferizada (~30s de packets na `packetQueue`) sem `avformat_seek_file` nem rede, reaproveitando o accurate-seek existente. Camada 2 (anel de retenção pra trás) fica explicitamente fora.

**Aceite (kanban):** seek de +10s/+30s dentro da janela não chama `avformat_seek_file` nem gera requisição de rede; o accurate-seek entrega o frame certo; seek longo cai no caminho atual sem regressão.

### Estado atual (verificado)

- `MEPlayerItem.seek(time:completion:)` (`MEPlayerItem.swift:823-842`): **as filas são descartadas na thread do chamador (`:831`) antes de qualquer decisão sobre o alvo**, e de novo na read thread (`:652`) após o `avformat_seek_file` (`:633`). O fast-path precisa interceptar antes de `:831`.
- Ramo `.seeking` do `readThread` (`:578-667`): `avformat_seek_file` com janela apertada `seekMin/seekMax` (`:629-633`); coalescing por `seekToTime != seekTime` (`:648-650`); clocks re-semeados (`:658-659`); `isSeek = true` (`:651`) alimenta `playable(...)` para reabrir com meio buffer.
- Accurate-seek **pronto para reúso**: `SyncPlayerItemTrack.seek` seta `seekTime` (`MEPlayerItemTrack.swift:97-107`), o callback de decode dropa frames até o alvo (`:173-188`). `options.isAccurateSeek` default `false`, **mas** o caminho `ClockProcessType.seek` (`MEPlayerItem.swift:971-973`) usa o mecanismo incondicionalmente — é o precedente a seguir.
- `AsyncPlayerItemTrack.seek` (`:294-301`) faz `packetQueue.flush()` — é isso que o fast-path evita.
- `CircularBuffer` (`CircularBuffer.swift`): **não tem peek não-destrutivo** (`search(where:)` em `:117-136` é destrutivo); `push`/`pop` sob `NSCondition` interna; `count` sem lock de propósito.
- Janela real: `loadedTime` é **estimativa por contagem/fps** (`PlayerDefines.swift:183-187`) — inútil para coverage. A janela verdadeira sai de `Packet.timestamp`/`timebase`/`isKeyFrame` (`Model.swift:195-229`).
- `seekByBytes` (`:607-624`) fica fora do escopo (containers TS/live — Icebox).
- Cache de disco: cobre replay/backward já baixado; forward não baixado bloqueia a read thread num fetch síncrono (`DiskCacheURLReader.swift:107-124,145-204`) — exatamente o pior caso que a camada 1 elimina.

### Design

Princípio de segurança: **tentativa otimista com degradação garantida** — se qualquer condição falhar, cair no caminho de rede (que re-flusha tudo), nunca num estado novo.

Regra estrutural que elimina a corrida (achado da revisão adversarial — uma versão anterior deste design drenava a fila pela read thread e podia perder o keyframe-alvo para a decode thread, corrompendo o decode e rebaixando o VideoToolbox permanentemente para software, `MEPlayerItemTrack.swift:190-198`): **quem drena a `packetQueue` é a própria decode thread — o único consumidor dela.** A read thread só decide; a drenagem acontece sem nenhum consumidor concorrente.

1. **`CircularBuffer` — novas APIs** (cada uma atômica sob o lock interno existente; sem tocar em `search`, que é destrutivo):
   - `peekEdges()` → `(first, last)?` não-destrutivo (para o coverage).
   - `scan(_ body:)` (ou equivalente) — varredura **não-destrutiva** de head→tail sob o lock, para localizar o índice do último keyframe com `ts ≤ alvo` e contar quantos itens o precedem.
   - `pop(count:)` — descarta exatamente N itens do head.
   Assinaturas finais a adequar ao estilo do arquivo; o essencial: `scan`+`pop(count:)` são chamados **só pela decode thread** (consumidor único), então o par não precisa ser atômico entre si — o produtor (read thread) só anexa no tail, o que nunca invalida um índice já contado a partir do head.
   **Correção da execução (2026-07-25):** a decode thread NÃO é o único consumidor da `packetQueue` de vídeo — `getVideoOutputRender` nos casos `.dropNextPacket`/`.dropGOPPacket` (`MEPlayerItem.swift:974-994` no HEAD base) também faz `pop` pela render thread. O predicate desses drops (`!item.isKeyFrame`) nunca remove um keyframe do head, e durante a janela de drenagem a `outputRenderQueue` está flushada (os drops exigem um frame no predicate do pop), mas o par `scan`+`pop(count:)` não é estruturalmente atômico contra esse consumidor. A implementação fecha a janela verificando, após o `pop(count:)`, que o head é **por identidade (`===`)** o packet escolhido no `scan`; divergência → falha limpa → caminho de rede.
   **Correção da revisão (2026-07-25):** verificar depois não basta — entre o `scan` e o `pop(count:)` um `packetQueue.flush()` do caminho de rede (ou um novo seek do usuário) pode esvaziar e reencher a fila, e aí o `pop` por CONTAGEM destrói packets pós-seek, incluindo o keyframe do novo GOP; nesse cenário a track já está em `.flush` e a re-sinalização de falha é suprimida, deixando o decoder retomar no meio do GOP. `pop(count:)` foi substituído por `drain(upTo: packet)`: uma única seção crítica que anda o head **por identidade** até o packet escolhido e, se ele não estiver mais na fila, **não descarta nada** e devolve falha. A verificação de identidade separada deixou de existir.
2. **Coverage por trilha** (`AsyncPlayerItemTrack`): `target ∈ (head.seconds, tail.seconds − margem]` da `packetQueue` via `peekEdges` (conversão por `timebase`). **Margem de segurança ~1s**: os timestamps estão em ordem de decode (pts com fallback dts, `Model.swift:218`) — com B-frames o tail não é o máximo exato de pts; a margem compra o caso reordenado ao custo de misses conservadores.
3. **Fast-path — decisão na read thread, drenagem na decode thread.** Novo sub-ramo no `.seeking` do `readThread`, antes do `avformat_seek_file`, guardado por `!seekByBytes && options.isMemorySeekEnabled && increaseSeconds > 0` (só forward) e `!isLoopModel`:
   - Read thread: checa coverage em **todas** as trilhas A/V habilitadas. Falhou → caminho de rede normal (nada foi tocado).
   - Passou → para cada trilha A/V, novo `fastSeek(to: target)` na track: seta `seekTime = target` (sob o `seekTimeLock` existente — reuso incondicional do accurate-seek, como `ClockProcessType.seek` já faz), `outputRenderQueue.flush()`, e um marcador `pendingDrain = target` (sob o `stateLock`); **sem** `packetQueue.flush()`.
   - Decode thread (no topo do loop de decode, `MEPlayerItemTrack.swift:268-291`): ao ver `pendingDrain`, executa `scan` (último keyframe ≤ alvo para vídeo; último item ≤ alvo para áudio) + `pop(count:)` deixando **o keyframe no head**, então `doFlushCodec()` e segue o consumo normal — o primeiro packet decodificado pós-flush é o keyframe, por construção (consumidor único). `scan` sem keyframe ≤ alvo (decode já consumiu além, caso raro) → track sinaliza falha.
   - Falha sinalizada por qualquer track → `MEPlayerItem` refaz o seek pelo caminho de rede (re-entrar `.seeking` com flag de força; o alvo ainda está em `seekTime`). Custo = o de hoje.
   - Sucesso: read thread **pula** `avformat_seek_file` e o `forEach { $0.seek }` da `:652`; seta `isSeek = true`, clocks (`:658-659`), completion. Coalescing (`:648`, `seekToTime != seekTime`) continua valendo antes do commit.
   - **Legendas: não tocar.** Sem flush: os `SubtitlePart` são selecionados por tempo (`search(for:)` drena a fila da trilha por tempo, doc 03) — itens pré-alvo simplesmente nunca são exibidos. Registrar verificação disso na revisão da fase.
4. **`seek(time:)` público**: com o fast-path habilitado, **não** chamar `allPlayerItemTracks.forEach { $0.seek }` na `:831` — a decisão migra para a read thread. Análise de deadlock (re-revisar na fase): read thread não bloqueia em push (packetQueue expansível, `CircularBuffer.swift:69-75`) e é acordada pelo `broadcast()`; decode thread presa em `outputRenderQueue.push` cheia era desbloqueada pelo flush da `:831` — passa a ser desbloqueada pelo `outputRenderQueue.flush()` do `fastSeek` (read thread) ou pelo flush da `:652` no caminho de rede; a read thread nunca espera a decode → sem espera circular. Nota honesta: se a read thread estiver presa num fetch síncrono do cache de disco (`DiskCacheURLReader.swift:175`), o fast-path só roda quando ela voltar — latência igual à de hoje nesse cenário (não é o caso comum do skip de +10s).
   **Correção da revisão (2026-07-25):** condicionar o skip do flush **à opção** (e não à elegibilidade real do fast-path) tem dois furos. (a) Com `syncDecodeVideo`/`syncDecodeAudio` (opções públicas) quem decodifica é a própria read thread, que pode estar bloqueada num `outputRenderQueue.push` cheio (fila não-expansível) — o único despertador era justamente o flush da thread do chamador, e sem ele o seek trava para sempre; `serveSeekFromMemory` recusa tracks sync, então o fast-path nunca compensa. (b) Todo seek que sabidamente não usa o fast-path (backward, alvo fora da janela, `seekByBytes`, remux) deixava de flushar no instante do pedido: áudio antigo continua audível até o `avformat_seek_file` voltar. Implementado: o skip passou a depender de um `isMemorySeekEligible(time:)` que repete as guardas da read thread (inclusive cobertura por trilha e tipo Async da track); e, no caminho de rede, o `forEach { $0.seek }` foi movido para **antes** do `avformat_seek_file`, cobrindo o TOCTOU entre a checagem do chamador e a decisão da read thread.
5. **`KSOptions`**: `isMemorySeekEnabled` instância + estática (default **true** — o aceite pede o ganho por padrão; a degradação garantida protege a regressão). Nome final em inglês neutro.
6. **Log/medição**: logar hit/miss do fast-path no `KSLog` existente do seek (`"seek to X spend Time"`) — é como o dono verifica "não tocou rede" sem ferramentas novas.

### Testes

- `CircularBuffer.peekEdges`/`scan`/`pop(count:)`: fixture class conformando `ObjectQueueItem` (timestamps/keyframes sintéticos) — scan acha o keyframe certo, pop(count:) deixa o keyframe no head, fila vazia, alvo além do tail, nada satisfaz → falha limpa.
- Coverage: função pura de janela com timebases diferentes (vídeo 1/1000, áudio 1/48000) e margem de B-frames.

### Commits sugeridos

- `feat: add non-destructive peek and bounded drain to the packet ring`
- `feat: serve forward seeks from the buffered packet window`
- `docs: describe the in-memory forward seek path` (docs/03, PT-BR)

### Riscos

- Terreno de threading frágil (`state` sem lock, `Sendable` de fachada) — mudanças mínimas, sempre pelo padrão existente; a revisão adversarial da fase usa as lentes de `context/review/concorrencia.md` e `playback-core.md`.
- Coalescing de seek durante o fast-path (`:648`) — manter a checagem `seekToTime != seekTime` antes de commitar o resultado.
- ABR/troca de trilha: trilha recém-habilitada tem fila vazia → coverage falha → rede (correto por construção).

---

## F4 — [[dv-nativo]] Dolby Vision dinâmico nativo — P5/P8 passthrough + P7→P8.1

**Objetivo:** VideoToolbox aplicando o tone-mapping dinâmico real da Dolby via remux: P5/P8 por passthrough (já entregue em grande parte — validar), e P7 dual-layer convertido para P8.1 single-layer (padrão `dovi_tool` mode 2) durante o remux.

**Aceite (kanban):** P5 e P8.1 tocam via `master.m3u8` com a TV em DV com metadata dinâmico (validação lado a lado com Infuse); P7 MEL e FEL convertem para P8.1 e tocam nativamente; sinalização HLS gerada do `DOVIDecoderConfigurationRecord`.

### Estado atual (verificado)

- **Passthrough P5/P8.1 já está no ar em código**: `ProAVVideoSignaling` (`ProAVPlaylist.swift:6-65` pós-F1) emite `dvh1` + `CODECS="dvh1.PP.LL"` + `VIDEO-RANGE=PQ` para (5,\*) e (8,1), e `hvc1`+`SUPPLEMENTAL-CODECS=".../db4h"` para (8,4); o `codec_tag` vira a FourCC do stream de saída (`MEPlayerItem.swift:330` pós-F1); `avcodec_parameters_copy` (`:329`) preserva o `AV_PKT_DATA_DOVI_CONF` e o movenc escreve o `dvcC`/`dvvC` (símbolo linkado, ver tabela de incógnitas); as RPUs (NAL 62) seguem inline no bitstream copiado; `preferredDisplayCriteria` sem rebaixo de DV (`ProAVPlayer.swift:122`). **O que falta em P5/P8.1 é validação de hardware, não código.**
- **P7 é recusado hoje**: `default: return nil` no signaling (`ProAVPlaylist.swift:41-42` pós-F1) → `"ProAV video signaling unsupported"` (`MEPlayerItem.swift:308-313` pós-F1) → fallback `KSMEPlayer`.
- **Struct Swift do record está um campo atrás do FFmpeg 8**: `DOVIDecoderConfigurationRecord` (`MediaPlayerProtocol.swift:153-168`) tem 8 `UInt8`; o record do FFmpeg 8 tem um 9º campo (`dv_md_compression`). Leitura por rebind é segura (só ignora o 9º); **escrita exige montar o registro completo de 9 campos**.
- **Precedente de shim para internals**: `FFmpegKit/Sources/FFmpegKit/include/avformat_shim.h:21-26` (expõe `ff_isom_write_vpcc`; stubs comentados para avcc/hvcc) — mesmo caminho serve se algo do Libdovi/libavformat precisar de protótipo manual.
- O caminho Metal/dv-fase0 (`DisplayModel.swift`, `isIPT`) é **outro pipeline** (engine FFmpeg) e não colide com nada de F4 — não tocar.
- Hack de NAL size: `extradata[4] == 0xFE → 0xFF` + `isConvertNALSize` (`FFmpegAssetTrack.swift:183-218`) — o parser de NALs do rewriter tem que respeitar o length size real do `hvcC`.

### Etapas

**F4a — Passthrough (código zero por default):**
1. Confirmar por leitura do `movenc.c` n8.1.2 as condições de escrita do `dvcC`/`dvvC` (side data presente + tag; conferir se exige `strict_std_compliance` — o remux já usa `-2`).
2. Produzir o checklist de validação hardware (abaixo). Só há código aqui se a leitura revelar um gap real (registrar antes de implementar).

**F4b — Conversor P7→P8.1 via Libdovi vendorizado:**
1. **Expor o Libdovi ao target Lumen**: `Libdovi.xcframework` já é dependência do FFmpegKit (`FFmpegKit/Package.swift:35,177-179`, header `rpu_parser.h`) e tem module map (`framework module Libdovi [system]`) — `import Libdovi` deve funcionar pelo mesmo mecanismo transitivo de `import Libavcodec` que `ProAVPlaylist.swift:3` já usa (Libdovi não é product declarado, mas os binary targets chegam via product FFmpegKit). Se não compilar assim, a rota é shim header no include do FFmpegKit (precedente `avformat_shim.h`) — **nunca** editar dependências do `Package.swift`.
2. **Novo `Sources/Lumen/MEPlayer/DOVIPacketRewriter.swift`** (nome final em inglês neutro, sem menção a ferramenta externa): opera sobre o `AVPacket` de vídeo no caminho de escrita do remux (`writeProAVPacket`, região `MEPlayerItem.swift:394-449` pós-F1):
   - Caminhar os NALs no formato length-prefixed (length size real do byte 21 do `hvcC`; **não** consultar `isConvertNALSize` — o recon confirmou que ele é exclusivo do caminho de decode VideoToolbox e a mutação `0xFE→0xFF` acontece só numa cópia local do extradata).
   - NAL type = `(byte0 >> 1) & 0x3F`. Type **63** (EL encapsulado) → **drop**. Type **62** (RPU) → `dovi_parse_unspec62_nalu` → `dovi_convert_rpu_with_mode(_, 2)` (P7→P8.1, descarta mapping de EL) → `dovi_write_unspec62_nalu` → substituir. Demais → copiar. **Emulation prevention é responsabilidade da API de NAL do Libdovi** (confirmado no `rpu_parser.h`: o parse aceita bytes "possibly escaped" e o write "escapes the bytes"). **Atenção:** `dovi_write_unspec62_nalu` retorna o buffer **já com o prefixo `0x7C01`** (header do NAL 62) — o reassembler escreve length prefix + bytes retornados verbatim, sem reinserir o header (senão duplica).
   - Reassemblar o packet com os length prefixes recalculados (`av_new_packet`/copiar props).
   - Qualquer erro de parse/convert em qualquer packet → falhar a sessão inteira (`onFailure`) → fallback `KSMEPlayer` (comportamento atual de P7; nunca entregar bitstream meio-convertido).
3. **Side data de saída**: quando a conversão está ativa, sobrescrever o `AV_PKT_DATA_DOVI_CONF` do `codecpar` de saída (entre `MEPlayerItem.swift:329` e `:331` pós-F1) com o registro de **9 campos** do FFmpeg 8: `dv_profile = 8`, `dv_bl_signal_compatibility_id = 1`, `el_present_flag = 0`, demais preservados, `dv_md_compression = none`. Montar os bytes manualmente (não estender o struct público de 8 campos — é API pública; registrar como dívida se a extensão for desejável depois).
4. **Signaling**: `ProAVVideoSignaling` aceita `(7, _)` quando a conversão está habilitada → `codecTag "dvh1"`, `CODECS "dvh1.08.LL"` (level preservado), `VIDEO-RANGE=PQ`, `preferredDynamicRange = .dolbyVision`.
5. **Gate**: `KSOptions.convertDolbyVisionProfile7` (default **true**; a degradação para `KSMEPlayer` em falha preserva o comportamento atual).
6. **MEL vs FEL**: mode 2 descarta a EL nos dois casos; FEL perde o refinamento (perda aceita pela indústria — mesmo trade-off do Infuse). Documentar no doc público com linguagem de produto ("converted to single-layer profile 8.1").

### Testes

- Walker/reassembler puro com NALs sintéticos (types 62/63/normais, length sizes 3 e 4, prefixo recalculado, packet só-EL, packet sem RPU).
- A conversão real do RPU (bytes válidos da Dolby) **não** é testável sem amostra — validação fica no hardware; o teste unitário garante a mecânica de empacotamento.

### Commits sugeridos

- `feat: expose the vendored libdovi api to the player target` (se necessário shim)
- `feat: rewrite dolby vision profile 7 packets as profile 8.1 during remux`
- `feat: signal converted profile 7 streams as dolby vision in hls`

### Riscos

- Reescrita de bitstream é o terreno de maior risco do plano inteiro (por isso F4 é a última fase e falha ⇒ fallback integral).
- CRC32/emulation prevention são responsabilidade do libdovi via API de NAL — se a verificação da etapa 2 mostrar o contrário, **parar** e registrar em Pendências (não reimplementar EPB à mão sem decisão do dono).
- Packets sem RPU em stream P7 (raros) → passar adiante sem erro.

---

## Estrutura do workflow (para o orquestrador)

Fases sequenciais; dentro de cada fase, paralelize só a revisão. Sugestão de ~12-16 agentes no total:

1. **Por fase (F1→F4):**
   - 1 agente **implementador**: relê a seção da fase + revalida refs de linha + implementa + escreve os testes + commits.
   - 2-3 agentes de **revisão adversarial em paralelo**, cada um com uma lente da casa (os checklists reais estão em `streamhub-app/docs/player/lumen/context/review/`): `ffmpeg-interop.md` + `memoria.md` (interop C, ownership, vazamentos), `concorrencia.md` + `playback-core.md` (threading, estados), e para F1/F4 a lente "spec HLS/ISOBMFF" (playlist e boxes contra a spec). Instrução explícita: tentar **refutar** que o código compila e está correto (tipos, assinaturas de API C contra os headers do FFmpegKit, conformância de protocolo membro a membro) — é a compensação por não poder buildar.
   - 1 agente de **correção** aplica o que a revisão confirmou; commits de fix separados (`fix: …`).
2. **Fase final (F5 — housekeeping):**
   - Atualizar no `lumen-player` (inglês/PT-BR conforme o arquivo): `docs/03-engine-meplayer-demux-e-pipeline.md` (§ProAV: remover "Atmos depende do muxer" e "Sem manipulação de RPU" conforme entregue; §Pegadinhas: fast-path de seek), `docs/02-camada-avplayer.md` (switchSource), `README.md` (tabela de paridade — **só afirmar o que o código faz**, regra do workspace), `ROADMAP.md` público (retirar o que foi entregue).
   - Atualizar no `streamhub-app`: `docs/player/lumen/ROADMAP.md` (baixa das tasks entregues conforme regras 2/3 do próprio arquivo) e escrever o relatório `docs/player/lumen/context/exec/agora-resultado-<data>.md` no formato de `proavplayer-mvp.md` (commits, decisões, pendências, como o dono valida).
   - Conferência final de higiene: `git -C lumen-player log` da branch sem atribuições/menções proibidas; nenhum arquivo fora do escopo tocado.
3. **Nunca**: rodar build/teste, push, tocar `Metal/` ou o caminho de decode do `KSMEPlayer`, adicionar dependência ao `Package.swift`.

---

## Checklist de validação do dono (hardware — pós-execução)

Amostras: `context/samples/SAMPLES.md` (F1: §E-AC-3 JOC; F4: §1 DV P5, §P8.1, §P7 MEL/FEL).

| Fase | Verificação | Como |
|---|---|---|
| F1 | Logo **Atmos** acende no receiver | amostra E-AC-3 JOC via ProAV |
| F1 | `dec3` com extensão type_a | `mp4box -diso init.mp4 \| rg -A4 dec3` sobre o workspace `Caches/Lumen-ProAV` (método do spike) |
| F1 | Sem regressão | AAC/AC-3/FLAC e TrueHD→FLAC continuam tocando; E-AC-3 **sem** JOC toca com `CHANNELS="6"` |
| F2 | Troca dub↔leg sem tela preta | trocar fonte no seletor com a flag ligada; frame atual permanece até o novo estar pronto; posição preservada |
| F2 | Fallback | desligar a flag → comportamento atual intacto |
| F3 | Seek +10s/+30s sem rede | log do player: fast-path hit, sem `"seek to … spend Time"` de rede; frame certo (accurate-seek) |
| F3 | Seek longo | cai no caminho de rede sem regressão |
| F4a | DV dinâmico real em P5 e P8.1 | lado a lado com Infuse na mesma amostra; OSD da TV em Dolby Vision |
| F4b | P7 MEL e FEL tocam como P8.1 nativo | amostras P7; TV em modo DV; sem artefatos |
| Pend. | Validações herdadas | retorno do modo de vídeo ao sair do playback (pendência antiga, re-observar) |

---

## Pendências pré-existentes que este plano NÃO cobre

- Read-ahead do cache de disco ([[read-ahead]], Próximo), HDR10+ ([[hdr10plus]], validação), seek-ram camada 2 (anel para trás), zero-delay camadas 3/4 (motor MEPlayer + handoff de áudio), prewarm especulativo de candidatos, primeira release taggeada + availability annotations (housekeeping do Próximo).
