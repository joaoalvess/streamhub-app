# Plano de fork — [[ffmpeg-8x]] FFmpegKit 6.1.4 → FFmpeg n8.1.2

**Data:** 2026-07-18 · **Método:** clone do `kingslay/FFmpegKit` @ `main` (`c32be9b`, o mesmo commit pinado no `Package.resolved` deste repo) + verificação de cada patch/flag/API contra os arquivos reais das tags `n6.1`, `n7.1.2`, `n8.0` e `n8.1.2` do mirror `FFmpeg/FFmpeg` (raw do GitHub). Sem nenhum build executado.

**Alvo recomendado: tag `n8.1.2`** — última patch release da série 8.1 (arquivo `RELEASE` = `8.1.2`; tags confirmadas: `n8.0`…`n8.0.3`, `n8.1`, `n8.1.1`, `n8.1.2`). O `README.md:64` deste repo cita 8.1.1 como a versão da build paga; 8.1.2 é a mesma série com mais bugfixes. O fix do Atmos no `dec3` (`complexity_index_type_a`, `movenc.c:412` em n8.1.2) existe desde `n8.0` e está ausente em `n6.1` e `n7.1.2` — confirmado por grep nas três tags (bate com [spike-ffmpegkit-614-resultado.md](spike-ffmpegkit-614-resultado.md)).

---

## Mudanças exatas no fork

### 1. Pin de versão

- `Plugins/BuildFFmpeg/main.swift:150` — `case .FFmpeg: return "n6.1"` → `return "n8.1.2"`. A URL de origem não muda (cai no `default:` de `Library.url`, main.swift:256-262 → `https://github.com/FFmpeg/FFmpeg`). O clone é `--depth 1 --branch n8.1.2` (main.swift:357-362).
- **Nenhum bump de biblioteca irmã é obrigatório.** Mínimos exigidos pelo `configure` do n8.1.2 (verificados no próprio configure): `dav1d >= 1.0.0` (pin atual 1.1.0 ✓, configure:7251), `libplacebo >= 5.229.0` (pin 6.338.2 ✓, :7358), `libass >= 0.11.0` (pin 0.17.1 ✓, :7243), gnutls/freetype/fribidi/harfbuzz sem versão mínima (:7231,7264-7266).
- **Exceção: `libmpv`** (pin v0.37.0, main.swift:162) é da era FFmpeg 6.1 e não compila contra FFmpeg 8. O KSPlayer não consome o produto `libmpv` — **não buildar** (deixar fora da lista `enable-`). O xcframework commitado fica stale (linkado contra 6.1); documentar no README do fork.

### 2. Patches que o FFmpegKit aplica hoje — status contra n8.1.2

| Patch | Onde | Status contra n8.1.2 |
|---|---|---|
| `videotoolbox.c`: troca `kCVPixelBufferOpenGLESCompatibilityKey` e `kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey` → `kCVPixelBufferMetalCompatibilityKey` (string replace em memória, não é .patch) | `BuildFFMPEG.swift:22-27` | **Aplica limpo.** As duas strings existem verbatim em `libavcodec/videotoolbox.c:821,823` do n8.1.2 |
| Cópia de headers internos para dentro do xcframework: `getenv_utf8.h`, `libm.h`, `thread.h`, `intmath.h`, `mem_internal.h`, `attributes_internal.h` (libavutil), `mathops.h` (libavcodec), `os_support.h` (libavformat), `internal.h` (libavutil), `config.h` | `BuildFFMPEG.swift:71-83` | **Todos existem no n8.1.2 com mesmo nome/local** (verificado por HTTP 200 em cada raw). Nenhum rebase |
| Edição de `internal.h`: comenta `#include "timer.h"` + replace da key OpenGL | `BuildFFMPEG.swift:84-92` | **Vira no-op inofensivo** — o `internal.h` do n8.1.2 não inclui mais `timer.h` nem menciona a key; `replacingOccurrences` sem match não falha. Os includes restantes (`libm.h`, `macros.h`, `attributes.h`, `config.h`) estão todos cobertos pelas cópias/headers públicos |
| Cópia de headers do **libpostproc** para o target `fftools` (só macOS/executáveis) | `BuildFFMPEG.swift:108-114` | **QUEBRA.** libpostproc foi removido da árvore no FFmpeg 8.0 (`libpostproc/postprocess.h` → 404 no n8.1.2). O `try FileManager.copyItem` lança e aborta o build da plataforma macos. **Remover as linhas 108-114** |
| Diretório `Plugins/BuildFFmpeg/patch/` | só `patch/libsmbclient/*` (8 patches de samba) | Não toca FFmpeg — nada a rebasear |

Agravante no mesmo bloco fftools (`BuildFFMPEG.swift:124-142`): a cópia de `src/fftools/*` é rasa (`contentsOfDirectory` não recursivo) e o fftools do n8.1.2 ganhou subdiretórios `graph/`, `textformat/` e `resources/` — os executáveis `ffmpeg`/`ffplay`/`ffprobe` do SPM não compilariam mesmo com a cópia consertada. Como o Player não usa esses executáveis, a recomendação é **neutralizar o bloco inteiro `if platform == .macos, arch.executable { ... }` (linhas 93-150)** no fork, em vez de consertá-lo.

### 3. Flags de configure — manter/adicionar

Toda a lista `ffmpegConfiguers` (`BuildFFMPEG.swift:256-367`) e os argumentos dinâmicos (`:165-250`) foram conferidos nome a nome contra `configure`, `allcodecs.c`, `allformats.c`, `allfilters.c` e `hwaccels.h` do n8.1.2:

- **REMOVER `--disable-postproc`** (`BuildFFMPEG.swift:268`) — a opção sumiu do configure junto com o libpostproc; opção desconhecida cai em `die_unknown` (configure:4565-4568) e **aborta o configure**. É a única flag inválida da lista inteira.
- **ADICIONAR `--enable-muxer=hls`** (junto ao bloco de muxers, `BuildFFMPEG.swift:287-291`) — exigência do [[proavplayer]] confirmada pelo spike (muxer `hls` ausente do 6.1.4). O select do configure puxa as dependências sozinho: `hls_muxer_select="mov_muxer mpegts_muxer webvtt_muxer"` (configure:3886) — `mov`/`mpegts` já estão na lista, `webvtt_muxer` entra automático. Opcional: `--enable-muxer=segment` (existe no n8.1.2) como plano B de segmentação.
- **MANTER `--enable-muxer=flac` e `--enable-encoder=flac`** (`:288,294`) — já presentes; são o transcode TrueHD/DTS→FLAC do [[proavplayer]].
- **MANTER `--enable-bsfs`** (`:314`) — habilita todos os bsfs; no n8.1.2 isso inclui `ff_dovi_rpu_bsf` (`bitstream_filters.c:36`) de graça. **Registrado para [[dv-nativo]]: `dovi_split` NÃO existe no n8.1.2** (ausente de `bitstream_filters.c`); o `dovi_rpu` só tem as opções `strip`/`compression` (`libavcodec/bsf/dovi_rpu.c:41-42`) — não converte P7→P8; o conversor próprio/`libdovi` vira obrigatório, como o ROADMAP já antecipava.
- Todos os demais componentes nomeados **existem no n8.1.2**: muxers (dash, hevc, m4v, matroska, mov, mp4, mpegts, webm*, nut), demuxers (todos os 33 da lista, incl. `eac3`, `hls`, `matroska`), decoders (incl. `truehd`, `dca`, `eac3*`, `dolby_e`, `sonic`, `snow`, `libdav1d`, `libzvbi_teletext`), encoders (incl. `alac`, `movtext`, `prores`, `*_videotoolbox`), filtros (incl. `yadif_videotoolbox`, `scale_vt`, `transpose_vt`, `estdif`, `w3fdif`, `*_vulkan`) e as opções gerais (`--enable-version3`, `--disable-swscale-alpha`, `--enable-thumb`, `--disable-linux-perf`, `--disable-hwaccel=av1_vulkan,hevc_vulkan,h264_vulkan` — sintaxe de lista com vírgula é suportada pelo configure).
- **Produtos irmãos para [[libass]]/[[fontes-embutidas]]:** o FFmpeg **não** linka libass (o branch `--enable-filter=ass` em `BuildFFMPEG.swift:239-241` nunca dispara porque `libass.isFFmpegDependentLibrary == false`, main.swift:265-276). `libass`/`libfreetype`/`libfribidi`/`libharfbuzz` são xcframeworks independentes, já commitados, com produto SPM próprio (`Package.swift:27` do FFmpegKit: `.library(name: "libass", targets: ["libfreetype", "libfribidi", "libharfbuzz", "libass"])`). **O bump não os toca — o critério de aceite "produtos irmãos continuam resolvíveis" se cumpre não mexendo em products/targets do Package.swift do fork.** Rebuild deles é opcional (BuildASS.swift usa `--disable-fontconfig --disable-require-system-font-provider`, ou seja CoreText no consumo — relevante para [[libass]] depois).

### 4. Resumo do diff do fork

1. `Plugins/BuildFFmpeg/main.swift:150` — `"n6.1"` → `"n8.1.2"`.
2. `Plugins/BuildFFmpeg/BuildFFMPEG.swift:268` — remover `"--disable-postproc"`.
3. `Plugins/BuildFFmpeg/BuildFFMPEG.swift:287-291` — adicionar `"--enable-muxer=hls"`.
4. `Plugins/BuildFFmpeg/BuildFFMPEG.swift:93-150` — neutralizar o bloco fftools/executáveis macOS (ou no mínimo remover as cópias de libpostproc, :108-114).
5. `Sources/Libav*.xcframework` — regenerados pelo build e recommitados (ou publicados como release assets — ver Hospedagem).
6. `Package.swift` do fork — sem mudança no modelo A; no modelo B trocar os `binaryTarget` de `path:` para `url:`+`checksum:`.

---

## Impacto no KSPlayer (Sources/KSPlayer — SÓ LEITURA nesta preparação; correções são de quem executar a task)

Varredura completa dos 15 arquivos que importam FFmpeg (`MEPlayer/*` + `Metal/PixelBufferProtocol.swift`), símbolo a símbolo, contra os headers do n8.1.2. O blast radius confirma a previsão do doc de pesquisa: pequeno. **Duas quebras duras, o resto compila.**

### Quebras duras (erro de compilação)

| Ponto | Problema | Correção esperada |
|---|---|---|
| `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:82` — `avcodec_close(codecContext)` | `avcodec_close` **removida no FFmpeg 8.0** (zero menções no `avcodec.h` do n8.1.2; presente no n6.1:2427) | Apagar a linha — o `avcodec_free_context(&self.codecContext)` da linha 83 já fecha e libera |
| `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:74` — `avcodec_close(codecContext)` (pegadinha já anotada em docs/04) | idem | Apagar a linha — `avcodec_free_context` na :76 cobre |

### Deprecations (compilam com warning em 8.x; quebram no FFmpeg 9)

| Ponto | Problema | Correção esperada |
|---|---|---|
| `Sources/KSPlayer/MEPlayer/FFmpegDecode.swift:47` — `codecContext.pointee.properties & FF_CODEC_PROPERTY_CLOSED_CAPTIONS` | `AVCodecContext.properties` deprecated no 8.0 (`FF_API_CODEC_PROPS`, avcodec.h:1643-1653 do n8.1.2); o define `FF_CODEC_PROPERTY_CLOSED_CAPTIONS` vive dentro do mesmo `#if` | Nada obrigatório agora. Fix futuro: criar o track de CC ao ver o primeiro side data `AV_FRAME_DATA_A53_CC` (o loop das linhas 68-87 já o lê) em vez de consultar `properties` |

### Pontos que mudaram de assinatura upstream mas devem compilar sem edição (verificar no primeiro build)

| Ponto | Mudança upstream | Por que deve passar |
|---|---|---|
| `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift:816-830` — closures do `avio_alloc_context` | `write_packet` ganhou `const uint8_t *buf` no FFmpeg 7.0 (lavf 61; `avio.h:235` no n8.1.2) → o parâmetro importa como `UnsafePointer<UInt8>?` | Os parâmetros das closures são inferidos, e `AbstractAVIOContext.read/write` já recebem `UnsafePointer<UInt8>?` (`Sources/KSPlayer/AVPlayer/PlayerDefines.swift:355-361`); conversão mutável→imutável é implícita |
| `Sources/KSPlayer/MEPlayer/Resample.swift:284` — `swr_convert(swrContext, &frame.data, outSamples, &frameBuffer, numberOfSamples)` | `swr_convert` virou `uint8_t * const *out` / `const uint8_t * const *in` no 7.0 (swresample.h:314 no n8.1.2) | O bridging `&Array` do Swift atende `UnsafePointer` e `UnsafeMutablePointer`; tipos de elemento já batem (`frameBuffer` já é `[UnsafePointer<UInt8>?]`, :275) |
| `Sources/KSPlayer/MEPlayer/FFmpegAssetTrack.swift:168` — `withMemoryRebound(to: DOVIDecoderConfigurationRecord.self)` sobre `AV_PKT_DATA_DOVI_CONF` | `AVDOVIDecoderConfigurationRecord` upstream ganhou `dv_md_compression` **no fim** do struct (lavu 59.30.100, 7.1) | O rebind lê só os campos iniciais, cujo layout não mudou. Opcional: estender o struct Swift espelho (`MediaPlayerProtocol.swift:153-162`) para expor a compressão — útil para [[dv-nativo]] |

### Confirmado sem impacto (já na API moderna)

- Side data de stream via `codecpar.coded_side_data`/`nb_coded_side_data` (`FFmpegAssetTrack.swift:164-171`) — o legado `av_stream_get_side_data` (removido no 7.0) não é usado.
- `AVChannelLayout`/`swr_alloc_set_opts2`/`av_channel_layout_*` em `Resample.swift`, `AVFoundationExtension.swift` — a grande quebra do 7.0 já foi absorvida.
- Nenhum uso dos campos legados de `AVFrame` removidos no 7.0 (`key_frame`, `interlaced_frame`, `top_field_first`, `pkt_pos`, `pkt_size`, `pkt_duration`, `palette_has_changed`); `AVFrame.side_data`/`nb_side_data` e `best_effort_timestamp` continuam públicos no n8.1.2 (`frame.h:624-625,698`).
- `avcodec_decode_subtitle2`, `avsubtitle_free`, `avcodec_flush_buffers`, `avcodec_alloc_context3`, `avcodec_parameters_to_context`, `avcodec_open2` (+`get_format`/`av_hwdevice_ctx_alloc(AV_HWDEVICE_TYPE_VIDEOTOOLBOX)` em `AVFFmpegExtension.swift:19-55`) — todos presentes e com assinatura igual.
- Demux/seek/IO: `AVFMT_FLAG_GENPTS/NOBUFFER/CUSTOM_IO`, `AVFMT_TS_DISCONT`, `AVFMT_NO_BYTE_SEEK`, `AVSEEK_FLAG_*`, `AVSEEK_SIZE`, `avformat_seek_file`, `av_read_frame`, `avio_feof/tell/open_dyn_buf/close_dyn_buf/wb32/write/open` — todos verificados no `avformat.h`/`avio.h` do n8.1.2.
- Muxing do `startRecord` (`MEPlayerItem+Recorder.swift:16-99`): `avformat_alloc_output_context2`, `avformat_new_stream`, `avcodec_parameters_copy`, `avformat_write_header`, `av_interleaved_write_frame`, `av_write_trailer` — API estável.
- libavfilter (`Filter.swift`): grafo `avfilter_*`/`av_buffersrc_*`/`av_buffersink_get_frame_flags` — estável. Nota não-obrigatória: `AVBufferSrcParameters` ganhou `color_space`/`color_range` no 7.0; a string de args de `AVFFmpegExtension.swift:385-398` pode passar a incluí-los ao trabalhar cor depois.
- swscale: o rewrite do 8.0 mantém `sws_getCachedContext`/`sws_scale` (`swscale.h:512,666` no n8.1.2) — `Resample.swift:44,115` intactos. Risco comportamental baixo; validar o caminho 10-bit/sem-OSType com amostra real.

Depois do bump validado, atualizar `README.md:64`, `docs/00-ARQUITETURA.md`, `docs/01-vis-o-geral-e-build.md` e este doc + [ffmpeg-version-bundled.md](ffmpeg-version-bundled.md) (regra 2 do ROADMAP).

---

## Hospedagem dos binários

Contexto: hoje os `binaryTarget` do FFmpegKit são todos `path:`-based (`Package.swift:135-236` do fork), com os xcframeworks commitados no repo (Libav* somam ~257 MB; maior arquivo individual do repo: 65 MB — abaixo do limite duro de 100 MB/arquivo do GitHub).

### Modelo A — igual ao upstream (mínimo esforço)

1. Rebuildar, deixar o script regravar `Sources/Libav*.xcframework`, commitar os binários no fork `joaoalvess/FFmpegKit`.
2. Tag semver casando com o FFmpeg: `git tag 8.1.2 && git push origin main --tags`. Se o push multi-GB estourar o limite de ~2 GiB/push do GitHub, dividir em 2-3 commits (ex.: Libavcodec num commit, resto no outro).
3. Neste repo: `Package.swift:46` → `.package(url: "https://github.com/joaoalvess/FFmpegKit.git", from: "8.1.2")`; `swift package update` regenera o `Package.resolved` (mantê-lo versionado).

Custo: clone multi-GB para todo consumidor (igual hoje). Zero mudança estrutural no Package.swift do fork.

### Modelo B — GitHub Release assets + checksum (recomendado: clones leves, sem risco de limite de arquivo)

1. Depois do build, zipar cada xcframework regenerado (o xcframework precisa estar na raiz do zip — `--keepParent` garante):
   ```fish
   cd ~/Developer/FFmpegKit
   for x in Sources/Libavcodec Sources/Libavdevice Sources/Libavfilter Sources/Libavformat Sources/Libavutil Sources/Libswresample Sources/Libswscale
       ditto -c -k --keepParent $x.xcframework (basename $x).xcframework.zip
   end
   ```
2. Computar o checksum de cada zip (comando oficial do SPM; rodar na raiz do pacote):
   ```fish
   swift package compute-checksum Libavcodec.xcframework.zip
   ```
3. No `Package.swift` do fork, trocar cada binaryTarget regenerado de `path:` para URL do release futuro + checksum:
   ```swift
   .binaryTarget(
       name: "Libavcodec",
       url: "https://github.com/joaoalvess/FFmpegKit/releases/download/8.1.2/Libavcodec.xcframework.zip",
       checksum: "<saída do compute-checksum>"
   ),
   ```
   Os xcframeworks **não rebuildados** (libass, libfreetype, libfribidi, libharfbuzz, gnutls etc.) podem continuar `path:` — mistura é permitida — ou migrar todos de uma vez para o clone ficar mínimo.
4. Commitar o Package.swift novo, remover os `Sources/Libav*.xcframework` do índice (se migrar tudo) e publicar o release **criando a tag no mesmo passo** (resolve o ovo-e-galinha URL⇄tag):
   ```fish
   gh release create 8.1.2 --target main --title "FFmpeg n8.1.2" *.xcframework.zip
   ```
   Limite de release asset: 2 GiB/arquivo — folga enorme (maior zip ~<100 MB).
5. Manter o fork **público** (GPL de qualquer forma): SPM não manda autenticação no download de asset de repo privado sem `.netrc` — repo privado aqui é atrito puro.
6. Neste repo, mesmo passo do modelo A: `Package.swift:46` → fork + `from: "8.1.2"`.

Cada rebuild futuro = novos zips + novos checksums + release novo (`8.1.3`, …) — mecânico, ~10 min além do build.

---

## Passo a passo de build para o dono

Pré-requisitos (uma vez):
- Xcode completo (xcodebuild/xcrun/lipo) + licença aceita; Homebrew.
- O script auto-instala o que faltar via brew (`pkg-config`, `nasm`, `sdl2`, `meson`, `cmake`, `texinfo`, `autoconf`, `automake`), mas pré-instalar evita pausas: `brew install pkg-config nasm meson ninja cmake autoconf automake libtool`.
- ~40-60 GB livres (fontes + scratch + xcframeworks) e o Mac ligado sem dormir (`caffeinate -dims` numa aba).

Passos:

```fish
# 1. Criar o fork e clonar (não existe fork do dono hoje — confirmado no doc de pesquisa)
gh repo fork kingslay/FFmpegKit --clone
cd FFmpegKit

# 2. Aplicar as 4 edições da seção "Resumo do diff do fork"
#    (main.swift:150, BuildFFMPEG.swift:268, :287-291, :93-150)

# 3. Build mínimo focado no StreamHub (recomendado)
#    - plataformas: só as que o Player realmente usa (corta xros/maccatalyst → ~35% menos tempo)
#    - bibliotecas: TLS (gmp→nettle→gnutls, ordem importa) + dav1d (AV1 sw) + FFmpeg
swift package --disable-sandbox BuildFFmpeg \
    platforms=tvos,tvsimulator,macos,ios,isimulator \
    enable-gmp enable-nettle enable-gnutls enable-libdav1d enable-FFmpeg
```

Notas de execução:
- O trabalho acontece em `.Script/` na raiz do clone; log de cada slice em `.Script/FFmpeg/<plataforma>/scratch/<arch>.log` (idem por biblioteca). Em falha, o erro real está no fim desse log.
- Re-execução com o argumento `notRecompile` pula bibliotecas que já têm `thin/<arch>/lib` pronto — é o mecanismo de retomada.
- **As dependências precisam ser buildadas antes do FFmpeg no mesmo `.Script`**: o configure só recebe `--enable-gnutls`/`--enable-libdav1d` se o diretório thin correspondente existir (`BuildFFMPEG.swift:231-248`). gnutls é obrigatório — sem ele o binário perde HTTPS e nenhum stream de debrid abre.
- O que o build mínimo **deixa de fora** vs o binário 6.1.4 shipped: protocolos `smb`/`srt`, decoder de teletexto `libzvbi_teletext`, filtro `vf_libplacebo` (e a cadeia MoltenVK/shaderc/lcms2) — nada disso é usado pelo StreamHub. Paridade total (se um dia quiser): acrescentar `enable-libshaderc enable-vulkan enable-lcms2 enable-libplacebo enable-libzvbi enable-libsrt enable-readline enable-libsmbclient` (+horas; samba é a parte mais frágil). Se fizer o build com vulkan no FFmpeg 8, novos hwaccels vulkan (vp9 etc.) entram no compile — pode ser preciso ampliar o `--disable-hwaccel=` da linha 283.
- Rebuild opcional dos irmãos de legenda (produtos já commitados servem): `enable-libfreetype enable-libfribidi enable-libharfbuzz enable-libass`.

**Tempo estimado (estimativa, Apple Silicon, build mínimo, 9 slices de arch):** gmp+nettle+gnutls ~1-2 h; dav1d ~15-30 min; FFmpeg ~1,5-3 h; empacotamento xcframework minutos. **Total: ~3-6 h.** Build de paridade total: mais 4-8 h.

```fish
# 4. Sanidade do artefato ANTES de publicar (30 s)
set LAF Sources/Libavformat.xcframework/tvos-arm64_arm64e/Libavformat.framework
rg FFMPEG_CONFIGURATION $LAF/Headers/config.h | rg -o 'enable-muxer=hls'         # deve aparecer
xcrun nm -arch arm64 $LAF/Libavformat | rg '_ff_hls_muxer'                        # símbolo definido
xcrun nm -arch arm64 Sources/Libavcodec.xcframework/tvos-arm64_arm64e/Libavcodec.framework/Libavcodec | rg '_ff_flac_encoder|_ff_dovi_rpu_bsf'
strings $LAF/Libavformat | rg 'Lavf62'                                            # libavformat major 62 = série 8.x

# 5. Publicar (Modelo A ou B da seção Hospedagem)

# 6. Neste repo (Player): apontar o pin e compilar
#    Package.swift:46 → .package(url: "https://github.com/joaoalvess/FFmpegKit.git", from: "8.1.2")
swift package update
swift build    # esperadas exatamente as 2 quebras de avcodec_close (correção na seção Impacto)
```

7. Validação de aceite (ROADMAP task 3, com [[sample-library]]): playback manual de MKV 4K HEVC/HDR10 e anime com ASS; harness `startRecord`→fMP4 com amostra E-AC-3 JOC e inspeção do `dec3` de saída (`ffprobe -show_data` / `mp4box -diso`) esperando `complexity_index_type_a` preservado; runtime check `av_bsf_get_by_name("dovi_rpu") != nil`; produtos `libass`/`libfreetype`/`libfribidi`/`libharfbuzz` resolvendo via SPM no fork novo.

---

## Riscos e plano B

1. **Configure/compile do FFmpeg 8 no cross-compile Apple** — as flags foram todas validadas estaticamente, mas só o build real prova o resto (asm novo, warnings-as-errors etc.). Mitigação: logs por slice + `notRecompile` para iterar barato. Plano B: recuar o pin para `n8.0.3` (série 8.0, mais rodada; o fix do `dec3` e o muxer `hls` já estão lá — só o `dovi_rpu` com `compression` e melhorias 8.1 ficam de fora).
2. **Patch textual do `videotoolbox.c` falhar silenciosamente em bump futuro** (é `replacingOccurrences`, sem erro se a string sumir — risco herdado, hoje verificado OK para n8.1.2). Mitigação barata no fork: transformar o replace em erro fatal quando não houver match.
3. **Regressão de decode/demux invisível** — a suíte de testes é no-op; qualquer regressão só aparece em teste manual. Mitigação: matriz mínima com [[sample-library]] (HEVC 4K HDR10, DV P8.1, E-AC-3 JOC, TrueHD, anime ASS 10-bit) antes de trocar o pin definitivo. Rollback: reverter `Package.swift:46` para `kingslay/FFmpegKit 6.1.4` é um commit — manter branch com o pin antigo até o aceite fechar.
4. **`FF_API_CODEC_PROPS` some no FFmpeg 9** — `FFmpegDecode.swift:47` vira quebra dura no próximo major. Anotado como fix futuro (migrar detecção de CC para side data A53).
5. **Peso do fork** — cada rebuild recommita ~300 MB de binários (Modelo A). Plano B já descrito: Modelo B (release assets) zera o crescimento do clone; ou `git gc`/branch órfã periódica.
6. **libmpv/libplacebo stale no fork** (linkados contra 6.1 se não rebuildados) — Player não consome; documentar no README do fork para ninguém usar esses produtos dali.
7. **arm64e em tvOS** — o próprio main.swift:1003 avisa que arm64e não tem ABI estável para libs de terceiros, mas o upstream shippa `tvos-arm64_arm64e` desde sempre; manter igual. Se o slice arm64e falhar no FFmpeg 8, plano B: restringir `PlatformType.tvos.architectures` a `[.arm64]` (main.swift:818-819) — o Apple TV real roda arm64.
8. **Sem muxer `hls` até o fork sair** — MVP do [[proavplayer]] pode nascer no 6.1.4 escrevendo a playlist m3u8 manualmente sobre fMP4 do muxer `mov` (rota 2 do spike), mas o Atmos (`dec3`) continua impossível sem FFmpeg ≥ 8.0 — o fork continua sendo o desbloqueio real.
9. **PR upstream** — se o bump sair limpo, oferecer PR ao `kingslay/FFmpegKit` (repo ativo) é bônus; não bloquear o roadmap esperando o maintainer (uma versão por vez, QA dele).

---

## Referências

- `kingslay/FFmpegKit` @ `c32be9b` (clone analisado): `Plugins/BuildFFmpeg/main.swift:150` (pin `"n6.1"`), `:96` (lista default de libs), `:256-262` (URL), `:357-370` (clone + patches), `:818-819`/`:1003` (arm64e); `Plugins/BuildFFmpeg/BuildFFMPEG.swift:22-27` (patch videotoolbox), `:71-92` (headers internos), `:93-150` (fftools/postproc), `:165-250` (args dinâmicos), `:256-367` (`ffmpegConfiguers`); `Plugins/BuildFFmpeg/BuildASS.swift:61-87`; `Package.swift:27` (produto `libass`), `:135-236` (binaryTargets `path:`).
- FFmpeg `n8.1.2` (raw.githubusercontent.com): `RELEASE`, `configure` (:3886 `hls_muxer_select`, :4565 `die_unknown`, :7231-7443 mínimos de deps; sem `postproc`), `libavcodec/videotoolbox.c:821,823`, `libavcodec/avcodec.h` (sem `avcodec_close`; :1643-1653 `FF_API_CODEC_PROPS`), `libavcodec/bitstream_filters.c:36` (`dovi_rpu`; sem `dovi_split`), `libavcodec/bsf/dovi_rpu.c:41-42`, `libavformat/movenc.c:412` (`complexity_index_type_a`; ausente em n6.1/n7.1.2), `libavformat/avio.h:235` (write_packet const), `libswresample/swresample.h:314`, `libswscale/swscale.h:512,666`, `libavutil/frame.h:624-698`, `libavutil/internal.h` (sem `timer.h`), `doc/APIchanges` (janelas 6.1→7.0→7.1→8.0), `Changelog` (seção 8.0), `fftools/` (subdirs `graph/`, `textformat/`, `resources/`), `libpostproc/postprocess.h` → 404.
- Este repo: `Package.swift:46`, `Sources/KSPlayer/MEPlayer/*` (linhas citadas na seção Impacto), `Sources/KSPlayer/AVPlayer/PlayerDefines.swift:347-377`, `docs/04-decodifica-o.md` (pegadinha do `avcodec_close`), [ffmpeg-version-bundled.md](ffmpeg-version-bundled.md), [spike-ffmpegkit-614-resultado.md](spike-ffmpegkit-614-resultado.md).
