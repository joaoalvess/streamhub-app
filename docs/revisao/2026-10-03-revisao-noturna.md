# Revisão noturna — 2026-10-03

Revisão autônoma do `streamhub-app` (foco) e do `lumen-player` (passada leve), feita só em código, sem simulador. Cada onda foi auditada por subagentes read-only, implementada com arquivos disjuntos por implementador, revisada por um revisor independente e só entrou em commit depois de um `build-for-testing` verde (workspace, `generic/platform=tvOS Simulator`, baixa prioridade). **Os testes compilam, mas não foram executados** — rodar no Xcode é o primeiro passo.

- App: PR https://github.com/joaoalvess/streamhub-app/pull/1 (`review/revisao-noturna` → `feat/paridade-infuse`)
- Lumen: PR https://github.com/joaoalvess/lumen-player/pull/1 (`review/revisao-noturna` → `feat/paridade-infuse`)
- O WIP da sessão anterior foi commitado antes em `feat/paridade-infuse` nos dois repos (app `dc4f7e2..1357af9`, lumen `5a5b304..530a475`) e publicado.

## Antes de validar

1. **Abrir pelo `StreamHub.xcworkspace`.** O `.xcodeproj` resolve o Lumen do GitHub (`main`) e não enxerga as mudanças locais do `../lumen-player`.
2. **Assinatura.** Os commits usam a identidade pessoal (time `J924GWS9NA`, bundle `joaoalvess.StreamHub`, extensão `joaoalvess.StreamHub.topshelf`, app group `group.joaoalvess.StreamHub`). O app group precisa estar registrado nesse time para assinar o Top Shelf. A troca local para a outra identidade de assinatura continua **só na working tree** (4 arquivos: `project.pbxproj`, `StreamHub/Info.plist`, os dois `.entitlements`), nunca commitada; uma cópia do diff está fora do repo.
3. **Rodar os testes** (`StreamHubTests` e `LumenTests`). Vários são novos e nunca rodaram (lista abaixo).

## O que mudou no app

### Onda 1 — estabilidade
| Commit | Mudança |
|---|---|
| `18e9d26` | Helper HTTP comum (`Support/HTTP.swift`): status, transporte, decode e **cancelamento mapeado para `CancellationError`**; `MetadataAPI` nonisolated, base resolvida uma vez, timeout de 10 s |
| `aff0240` | Home não fica presa em loading quando o load é cancelado |
| `cfb2ccb` | `RequestGate` sem spin; sem retry depois de cancelar; `retry-after`/`ratelimit-reset` limitado a 0–30 s |
| `0655d49` | Play que termina depois de a janela fechar é descartado (geração de play); reporter do Jellyfin recebe a última posição nativa |
| `d083317` | Instalação do Infuse checada a cada play |
| `97957fa` | Login do Jellyfin single-flight; retry 401 com o token atual |
| `d0d9dd1` | Biblioteca volta ao estado inicial quando o load é cancelado; play com guarda e `stop()` do reporter anterior |
| `bdd800b` | `SecretsStore` normaliza URL, só grava se mudou, descarta token/userId do Jellyfin quando servidor/usuário muda |
| `fdfc2cb` | Página de catálogo que falhou é re-tentada (não marca fim da lista); prefetch sob demanda |
| `f20289f` | Flags de assistido legados e buscas recentes migram para o perfil |
| `0b057fd` | Top Shelf limpo quando o perfil some; deep link fecha a janela atual antes de abrir |

### Onda 2 — performance
| Commit | Mudança |
|---|---|
| `25b2410` | Pipeline de imagens (`Images/ImagePipeline.swift` + `RemoteImage`): downsampling ImageIO, cache em memória limitado (120 MB), dedupe de downloads, URLCache em disco; substitui todos os `AsyncImage`; TMDB `original` → `w1280`/`w500`; hero com crossfade e prefetch dos próximos |
| `00fba31` | `AsyncTTLCache` (TTL + LRU + single-flight) para metadados (30) e streams (10); `HTTP.fetch` `@concurrent` — Streams/Jellyfin/WatchHub decodificavam na main por causa do `NonisolatedNonsendingByDefault` |
| `e670c6d` | Load da Home/Biblioteca pertence ao VM (trocar de aba não corta o carregamento); rows aparecem em ordem conforme chegam; ids estáveis no Continue assistindo/recentes (cards não são recriados a cada render) |
| `39adc15` | Janela de detalhe: backdrop compartilhado com o carrossel (sem download duplo nem decode cheio na main), reveal quando imagem e slide estão prontos (0,45 s em vez de 0,7 s fixo), debounce de 350 ms no `loadSeries`, planejamento de episódios fora da main, próximo episódio em cache, carrossel libera imagens distantes |

### Onda 4 — features que faltavam
| Commit | Mudança |
|---|---|
| `2ce4325` | Stores: Minha lista por perfil (`MyListStore`), remover do Continue (descarta sessões pendentes), marcar/desmarcar assistido, remover/limpar buscas, `isCompleted` com duração real |
| `91f26d1` | Botões Reproduzir/+/Info do hero funcionando (Reproduzir abre com autoplay); row "Minha lista" na Home; "Remover de Continuar assistindo" (long press) |
| `c5e2325` | Remover busca recente (long press) e botão "Limpar" |
| `7b06435` | "+" e "i" no detalhe; "Marcar como assistido/não assistido" no card de episódio (long press), avançando o Continue para o próximo episódio |
| `a4cf90e` | Removidos os selos 4K/Dolby Vision/Atmos/CC/AD que apareciam fixos em todo título |
| `64faf4f` | Reabre a última seção do menu por perfil (busca não é restaurada) |
| `72728c3` | "Assistido" no player nativo usa a duração real do arquivo em vez do runtime do catálogo |
| `c78bc25` | Grid completo da Biblioteca não trava em loading ao reaparecer no meio do load |

### Onda 6 — testes (novos, nunca executados)
`82f7cff`: `HTTPTests` (stub `URLProtocol`), `TopShelfPublisherClearTests`, `PlaybackGenerationTests`, `CatalogRowTests`. Também novos nas ondas anteriores: `AsyncTTLCacheTests`, `HomeProgressiveLoadingTests`, `MediaItemStableIDTests`, `MyListStoreTests`, `MenuSectionRestoreTests`, extensões de `PlaybackProgressStoreTests`, `RecentSearchesStoreTests`, `NativePlaybackSessionTests`, `StreamsAPITests`.

### Onda 3 — refatoração estrutural (sem mudança de comportamento; SHA antes: `82f7cff`)
| Commit | Mudança |
|---|---|
| `0dd2ff5` | `ResumePolicy` único (30 s mínimo, 95% "perto do fim", 92% "concluído") no lugar de 3 cópias; `PlaybackProgressStore.entry(forSeries:)`; `ResumePolicyTests` |
| `1e26423` | `PlaybackCoordinator` 677 → 485 linhas: `NativePlaybackSession.swift` e `nonisolated enum PlaybackRequest` (forwarders mantidos para os testes) |
| `36e3a03` | `MediaWindowView` 649 → 519 linhas: `MediaWindowSupport.swift` e `nonisolated enum PlayPlanner` (decisão de play pura) com `PlayPlannerTests` (18 casos) |

Se algo da W3 incomodar, ela reverte sozinha: `git revert 36e3a03 1e26423 0dd2ff5`.

## O que mudou no Lumen
| Commit | Mudança |
|---|---|
| `80cd009` | `DiskByteCache` orça por bytes gravados (antes, ler o fim de um arquivo grande apagava as outras entradas); índice re-tentado se a gravação falha |
| `b02e6a9` | Resposta 206 com `Content-Range` diferente do pedido é rejeitada (não envenena o cache) |
| `8244cf5` | Seek em stream não seekable é descartado após 2 s de graça (antes o player ficava parado para sempre); seek falho não re-executa em loop |
| `2a18662` | Seek durante o commit da troca de fonte é adiado (antes abortava o switch e apagava o diretório do item vivo); re-emitido em abort que não seja shutdown/falha |
| `8e79b45` | Servidor de loopback envia corpo sem copiar o range inteiro; diretório → 404; start pendente resolvido no shutdown |
| `7d1fff4` | Thumbnails do scrubber liberam decoders no `deinit`; até 200 pacotes por quadro |
| `8b9eb55` | Scrubber cancela a edição ao sair da janela (antes o player ficava pausado); aba de continuação vazia escondida |
| `b7a75c9` | Alvo de um seek falho só vale como posição de fallback por 10 s |
| `7ac4f78` | README e docs corrigidos contra o código (rewind, teto de 48 kHz no transcode, HDR10+ fora do "planejado", requisito Xcode 16+, emojis) e docs/02–03 com o comportamento novo |

## Checklist do simulador (ordem sugerida)

1. **Home**: abrir, trocar de aba durante o carregamento e voltar (deve continuar o mesmo load); rows chegando não podem pular foco/scroll; hero ganhando itens (pontinhos); crossfade do hero sem spinner; "Tentar novamente" após falha (desligar rede).
2. **Imagens**: nitidez de pôster (800 px), card largo, backdrop do hero (`w1280`) e logo (`w500`) numa TV 4K; nenhum pôster "trocado" ao rolar rápido.
3. **Detalhe**: overlay entra aos ~0,45 s (ver se não destoa do slide); abrir sem autoplay durante a apresentação do cover; carrossel rápido (debounce) não mostra série errada; foco ao trocar temporada e nos especiais; **foco pode se perder** quando a seção de episódios aparece depois do reveal (risco pré-existente, mais provável agora).
4. **Long press (contextMenu)** nos cards do Continue, Minha lista, buscas recentes e episódios: abre o menu sem disparar play; foco depois de remover o último item da row (a row some).
5. **Hero**: Reproduzir abre com autoplay no item certo; "+" alterna para check; Info abre o detalhe.
6. **Marcar assistido** no episódio em andamento avança o Continue; desmarcar não restaura o Continue (limitação conhecida).
7. **Player nativo**: assistir até ~92% de um arquivo mais curto/longo que o runtime e conferir "assistido"; troca de fonte com seek no meio (Lumen); stream sem seek (deve começar do início após 2 s se não for seekable); scrubber ao sair da tela.
8. **Biblioteca**: abrir/fechar rápido, grid completo, play duplo (não pode criar duas sessões).
9. **Perfis**: apagar perfil limpa Top Shelf e Minha lista; última seção do menu volta por perfil.

## Propostas (não implementadas — decisão do dono ou precisa de device)

- **R2-13 — URL do aiometadata com UUID hardcoded** em `StreamHub/Catalog/MetadataAPI.swift` (repo público): mover para `Secrets.plist`/Keychain e **rotacionar o UUID**.
- **Próximo episódio no player nativo** (P1 + aba "continuar" do Lumen): exige API genérica no Lumen (`nextItem` + callback) e fluxo no app; a aba vazia foi só escondida.
- **F24**: remover carrossel/hero da árvore durante o playback nativo (memória).
- **F15**: as 16 seções da TabView mantêm `HomeViewModel`s vivos — cache compartilhado de catálogos ou liberar ao sair.
- **F18**: `fields=MediaStreams` em toda listagem do Jellyfin (payload grande).
- **R2 JSONDefaults / R11 MockData**: helper de persistência comum e remoção do `MockData` (hoje só alimenta um Preview) — baixo valor, deixados de fora para não poluir o diff.
- **SecretsStore testável**: extrair normalização/limpeza para funções puras (hoje tudo passa pelo Keychain real).
- **Lumen**: R4-06 (freeze frame via IOSurface em vez de `VTCreateCGImage` na main), R4-07 (VideoOutput sempre anexado — verificar DV em hardware), R4-14 (`av_write_frame` ignorado no transcode legado), outros caminhos de abort durante o commit da troca de fonte (`beginSourceSwitch`, `selectAudioTrack(.abortPending)`, desligar legenda), slicing de 206 que começa antes do offset, strings PT-BR hardcoded na UI tvOS do framework.
- Decisões já documentadas mantidas como estão: `isSubscribed` hardcoded, stub de `titleDeepLink`, modo Enhanced, icebox do Lumen.

## Riscos e limitações conhecidas

- `AsyncTTLCache` não devolve cedo para um chamador cancelado (espera o load, até 10 s); as gerações de play evitam efeito errado.
- `MetaProvider` cacheia `meta: null` por 10 min.
- `markEpisodeWatched` só avança o Continue se houver próximo episódio na ordem; especiais removem a entrada.
- Minha lista sem limite de tamanho e identidade só por `contentId ?? imdbId` (o mesmo título vindo de outro catálogo não é reconhecido).
- `CatalogRow.onCardAppear` limpa `fetchFailed` a cada card que aparece: sem rede, cada movimento de foco no fim da row refaz uma requisição (uma por vez, por causa de `isFetching`).
- `failedLogoURL`/`failedPosterURL` são permanentes por instância de view (falha transitória mantém o texto/placeholder até a view ser recriada).
- Chave `menu.lastSection.<uuid>` fica no UserDefaults depois de apagar o perfil.
- Residuais do W1 ainda abertos: callback tardio de erro do Infuse pode mostrar alerta na janela seguinte; trocar de perfil pelo Top Shelf durante sessão da Biblioteca não envia `.stopped`; `Task.yield()` no deep link pode não bastar (validar em device); `jellyfinDeviceId` não muda com o usuário.
- Lumen: o servidor de loopback ainda lê o range pedido inteiro para a memória antes de enviar (`ProAVHTTPServer.proAVRead`); com segmentos HLS é pequeno, mas um GET sem `Range` num arquivo grande alocaria o arquivo todo — proposta: enviar em blocos de ~1 MB. Bytes após `\r\n\r\n` (pipelining) são descartados (AVPlayer não faz pipelining).
- Lumen: o intent de seek falho vale como alvo de fallback por até 10 s; `cancelSourceSwitch()` chamado por `stop()`/`set(url:)` ainda pode re-emitir um seek adiado na engine que vai ser desligada (sem vazamento, só trabalho inútil).

## Avisos

- **`origin/main` foi reescrito** nos dois repos (só remoção de emojis do README). `feat/paridade-infuse` parte do `main` antigo; não rebaseei. O README do Lumen também teve emojis removidos neste branch — um rebase futuro pode conflitar ali.
- **CI do Lumen não roda nestes branches**: `.github/workflows/build.yml` filtra `branches: '*'`, que não casa nomes com `/` (`feat/...`, `review/...`), tanto em push quanto no base do PR.
- **Credenciais em texto puro** em `appletv/.claude/settings.local.json` (token e senha). Não li nem copiei; vale mover para o Keychain e rotacionar.
- Exceção de build usada só nesta tarefa: `build-for-testing` em baixa prioridade (`taskpolicy -b`, `nice 19`, `-jobs 2`), DerivedData próprio em `~/Library/Developer/Xcode/DerivedData/StreamHub-revisao-noturna` (pode apagar).
