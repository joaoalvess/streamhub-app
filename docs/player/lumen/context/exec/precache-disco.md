# Exec — [[precache-disco]] Precache em disco (DiskByteCache)

**Branch:** `task/precache-disco` (worktree em `/private/tmp/claude-501/-Users-joaoalves-Developer-StreamHub/113db3ca-fa39-47b3-8e07-30a97e5e0f39/scratchpad/wt-precache-disco`, base `1b8b46f`)
**Status:** implementado e commitado; validação em device pendente (dono).

## Commits

| Hash | Mensagem |
|---|---|
| `4d3bbe4` | feat: add disk byte cache with range index and lru eviction |
| `d246164` | feat: add ranged http reader backed by disk byte cache |
| `856e475` | feat: add disk cache avio context for the ffmpeg engine |
| `a707bf7` | feat: add disk cache resource loader for avplayer |
| `090f28e` | feat: replace dead cache flag with disk cache options |
| `cf983b2` | feat: install disk cache resource loader in ksavplayer |
| `163ccda` | test: cover disk byte cache range index and quota |
| `dded0bd` | fix: release custom avio context when ffmpeg open fails (revisão) |
| `c0dbbb2` | fix: bypass disk cache for hls playlist urls (revisão) |
| `4ff5381` | fix: clamp resource loader data requests at end of file (revisão) |

## Arquivos tocados

- **`Sources/KSPlayer/Cache/DiskByteCache.swift` (novo)** — núcleo Swift-puro: um arquivo `<sha256(chave)>.data` (esparso, escrito via `pread`/`pwrite` POSIX — sem FileHandle para evitar ObjC exceptions e problemas de availability) + sidecar `<sha256>.index` (JSON: versão, contentLength, contentType, lista de ranges). Ranges são mesclados/ordenados no insert; leitura só serve intervalo 100% coberto. Quota rígida: antes de cada write que cresce o arquivo, checa `outrosEntries + tamanhoProjetado > maxBytes`; tenta eviction LRU das outras entradas (por data de modificação; a entrada ativa nunca é evictada) e, se ainda estourar, para de gravar (`isWritable = false`) — leitura do que já está em disco continua. Crash-safety: dados são `pwrite` + `fsync` antes de o índice ser persistido (atomic write, flush a cada 8 MiB e no close); índice inválido/maior que o arquivo → reset silencioso do cache daquela entrada; `pread` curto (purge do SO) → devolve `nil` e o chamador cai para rede.
- **`Sources/KSPlayer/Cache/DiskCacheURLReader.swift` (novo)** — camada rede+cache compartilhada pelos dois motores. `read(at:maxLength:)` serve do `DiskByteCache` se coberto; senão faz GET com `Range: bytes=a-b` em chunks de 1 MiB (read-ahead implícito: o FFmpeg pede 32-256 KiB e o chunk excedente já fica em disco), grava no cache e devolve. Fetch é síncrono via `URLSession` delegate + semáforo, com cancelamento do task assim que os bytes pedidos chegam (protege contra servidor que ignora `Range` e mandaria o arquivo inteiro). `contentLength` vem do `Content-Range` da primeira resposta 206 e fica persistido no índice; resposta 200 (servidor sem suporte a range) → `prepare()` falha e o chamador faz fallback. `close()` cancela task em voo e invalida a sessão (dois locks separados: fetch e estado — close não bloqueia atrás de um fetch em andamento).
- **`Sources/KSPlayer/MEPlayer/DiskCacheAVIOContext.swift` (novo)** — subclasse de `AbstractAVIOContext` (buffer avio de 256 KiB): `read` → `reader.read` (EOF → `AVError.eof.code`, falha → `swift_AVERROR(EIO)`); `seek` trata SEEK_SET/CUR/END com máscara de `AVSEEK_FORCE` (0x20000); `fileSize()` devolve o tamanho aprendido no `prepare()`. Init é failable: sem `Content-Length` confiável ou sem suporte a range → `nil` → `MEPlayerItem` segue pelo caminho http normal do FFmpeg (fallback transparente).
- **`Sources/KSPlayer/AVPlayer/DiskCacheResourceLoader.swift` (novo)** — `AVAssetResourceLoaderDelegate` sobre o mesmo `DiskCacheURLReader`. Truque de scheme: `ksdiskcache-https://...` força o AVPlayer a rotear tudo pelo delegate (`assetURL(for:)`/`originalURL(for:)`). `contentInformationRequest` recebe length/`isByteRangeAccessSupported=true`/UTI (via `UTType(mimeType:)` quando disponível, fallback para mapa fixo, default `public.mpeg-4`); `dataRequest` é servido em chunks de 512 KiB numa fila concorrente própria, checando `isCancelled` entre chunks.
- **`Sources/KSPlayer/AVPlayer/KSOptions.swift`** — aposentada a flag morta `cache` (nunca lida; comentário do autor upstream já a declarava quebrada — `ff_tempfile` com `/tmp` hardcoded). Novas opções: `diskCacheDirectory: URL?` (nil = desligado; default a estática `KSOptions.diskCacheDirectory`), `diskCacheMaxBytes: Int64` (default estática, 2 GiB) e `diskCacheKey: String?` (chave estável por título fornecida pelo app). `process(url:)` default agora devolve `DiskCacheAVIOContext` quando `diskCacheDirectory` está setado e a URL é http/https (subclasses que sobrescrevem continuam mandando). Helpers: `diskCacheKey(for:)` (fallback: URL sem query string — remove token rotativo de debrid) e `diskCacheHTTPHeaders()` (junta `avOptions[AVURLAssetHTTPHeaderFieldsKey]` + `userAgent` + `referer` para as requisições do cache).
- **`Sources/KSPlayer/AVPlayer/KSAVPlayer.swift`** — `init` e `replace(url:options:)` passam por `makeAsset(url:options:)`: com cache ligado, cria o `AVURLAsset` com o scheme trocado e instala `resourceLoader.setDelegate` (loader retido em `cacheResourceLoader`); `replace` fecha o loader anterior. Sem cache, comportamento idêntico ao anterior.
- **`Tests/KSPlayerTests/DiskByteCacheTest.swift` (novo)** — cobre merge de ranges adjacentes, gap não servido, persistência do índice entre reopens (dados + contentLength + contentType) e eviction LRU por quota entre duas entradas.

## Decisões

1. **Rota nativa `cache:`/`async:` do FFmpeg descartada** conforme a pesquisa (`context/roadmap/precache-data-to-hard-drive.md`): `/tmp` hardcoded em `libavutil/file_open.c` quebra em tvOS sandboxed. Tudo é Swift puro, zero mudança em Package.swift/FFmpegKit.
2. **Um núcleo, dois adaptadores finos** — `DiskByteCache` + `DiskCacheURLReader` compartilhados; `DiskCacheAVIOContext` (MEPlayer) e `DiskCacheResourceLoader` (KSAVPlayer) são só tradução de API, como a pesquisa recomendava.
3. **Read-ahead por chunk em vez de thread produtora** — o over-read de 1 MiB por requisição já dá read-ahead sequencial e reduz número de requests ao debrid (risco de rate-limit apontado na pesquisa); uma thread produtora dedicada ficou como evolução futura, não é exigida pelo critério de aceite.
4. **Fallback transparente em todos os furos** — init failable (sem range support/sem length) → caminho http normal; `pread` curto ou arquivo purgado pelo SO → rede; índice corrompido → reset da entrada. O cache nunca é fonte de verdade.
5. **Ligar/desligar por `diskCacheDirectory`** (nil = off), seguindo o desenho do ROADMAP; sem flag booleana redundante.
6. **POSIX I/O direto** (`open`/`pread`/`pwrite`/`fsync`) no lugar de `FileHandle`: APIs throwing do FileHandle exigem tvOS 13.4+ (mínimo do pacote é 13.0) e as legadas estouram NSException em disco cheio.

## Correções da revisão

1. **Leak em falha de open (MEPlayerItem)** — com o cache ligado por default, `avformat_open_input`/`avformat_find_stream_info` falhando deixavam o `DiskCacheAVIOContext` retido para sempre (fd + URLSession abertos): `avformat_close_input` nunca fecha `pb` custom (`AVFMT_FLAG_CUSTOM_IO`). Agora os três early-returns de `openThread` chamam `releaseCustomIO` (close + balanço do `passRetained`).
2. **HLS quebrado no KSAVPlayer com cache ligado** — `.m3u8` https ia para o resource loader; URLs relativas de segmento resolvem contra o scheme `ksdiskcache-https` e o delegate serviria os bytes da playlist para qualquer request. No MEPlayer, playlist live cacheada = playlist stale no reopen. `canCache(url:)` e `assetURL(for:)` agora recusam extensões `m3u8`/`m3u`.
3. **EOF no resource loader** — dataRequest com range além do `contentLength` entrava no loop, recebia `Data()` vazio e finalizava com `networkConnectionLost` espúrio; agora `remaining` é clampado a `total - offset` e finaliza limpo.

## Pendências / limitações conhecidas

- **Servidor sem suporte a `Range`**: MEPlayer cai para o http do FFmpeg (ok); no KSAVPlayer o asset falha e o `KSPlayerLayer` faz o fallback padrão para o `KSMEPlayer`. Não tratado inline.
- **Interrupt durante fetch**: o `interrupt_callback` do FFmpeg não alcança AVIO custom; um shutdown no meio de um fetch espera o timeout da requisição (30 s) no pior caso. Mesma classe de problema do http normal; mitigável com uma thread de read-ahead no futuro.
- **AirPlay**: asset com resource loader não toca em external playback (limitação do AVFoundation). Se AirPlay for cenário real, o app deve desligar `diskCacheDirectory` quando a rota wireless estiver ativa.
- **Sem thread de read-ahead dedicada** (ver decisão 3).
- **Token de debrid renovado no meio da sessão**: as requisições do reader usam a URL passada no open; se o link expirar no meio do playback, o fetch falha e o erro sobe como erro de rede normal (sem re-resolução automática).
- Testes cobrem só o núcleo `DiskByteCache`; reader/AVIO/resource loader validam-se em device.
- **Detecção de HLS por extensão** (`m3u8`/`m3u` no path): playlist servida por URL sem extensão (ou só com query) ainda passa pelo cache — se o StreamHub tiver esse caso, desligar `diskCacheDirectory` para essa URL no app.
- **Quota entre instâncias simultâneas**: `otherEntriesBytes` é amostrado no init/eviction; dois títulos gravando ao mesmo tempo podem exceder a quota momentaneamente até a próxima checagem.

## Como validar no Apple TV

1. No StreamHub, antes de criar o player: `options.diskCacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("KSPlayerDiskCache")`, `options.diskCacheKey = "<imdbId>.<perfil-de-stream>"` (chave estável por título, não a URL), opcional `options.diskCacheMaxBytes`.
2. **Critério principal (re-seek sem rede)**: tocar um stream http de debrid no `KSMEPlayer`, assistir ~1 min, seek para frente, seek de volta ao trecho já visto → o trecho revisitado deve servir do disco. Verificável com proxy (Proxyman/mitmproxy no Mac como proxy do Apple TV): nenhuma requisição `Range` nova para intervalos já baixados; ou por log do provedor.
3. **Persistência**: matar o app, reabrir o mesmo título (mesma `diskCacheKey`) → playback do início não gera requisições para os primeiros MiB; conferir no container do app `Library/Caches/KSPlayerDiskCache/<sha>.data`/`.index`.
4. **Quota/LRU**: setar `diskCacheMaxBytes` baixo (ex. 200 MiB), tocar dois títulos → arquivos do título mais antigo somem quando o segundo estoura a quota.
5. **Caminho KSAVPlayer**: tocar um MP4 direto (motor primeiro = `KSAVPlayer`) com cache ligado → deve tocar normalmente via scheme `ksdiskcache-https` e repetir o teste do item 2.
6. **Regressão com cache desligado** (`diskCacheDirectory = nil`): comportamento tem de ser byte-a-byte o anterior nos dois motores.
7. Testes de unidade: rodar o target `KSPlayerTests` (novo `DiskByteCacheTest`).
