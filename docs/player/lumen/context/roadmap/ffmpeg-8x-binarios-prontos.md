# Binários prontos de FFmpeg ≥ 8.0 pra tvOS — resultado da investigação [[ffmpeg-8x]]

**Data:** 2026-07-18 · **Método:** enumeração de releases via `gh`, download dos zips reais do candidato finalista e prova por símbolos (`xcrun nm`/`strings`/`lipo`) nos slices tvOS + `FFMPEG_CONFIGURATION` baked no `config.h`, comparado com o layout que o `Package.swift` do FFmpegKit pinado (`kingslay @ c32be9b`) declara e que `Sources/KSPlayer` importa. Nenhum build executado.

## TL;DR

**Existe binário público pronto: MPVKit release `0.41.0-n8.1.2` (github.com/mpvkit/MPVKit), FFmpeg n8.1.2 exato, com slices tvOS device+simulator e layout de módulos idêntico ao do FFmpegKit.** Atende 6 dos 7 requisitos — falha exatamente em um: **o muxer `hls` continua desabilitado** (o MPVKit herdou a mesma whitelist de muxers do script do kingslay). Consequência: o build de horas do dono **deixa de ser pré-requisito para o desbloqueio principal** ([[proavplayer]] Atmos via `dec3` + FLAC + FFmpeg 8 + TLS) usando a rota 2 do spike (playlist m3u8 manual em Swift sobre fMP4 do muxer `mov`, agora **sem** a limitação Atmos). O build próprio só continua necessário se quisermos o muxer `hls` nativo — ou sai via PR de 1 linha ao MPVKit.

## Veredito por candidato

### 1. kingslay/FFmpegKit — REPROVADO
- `gh release list --repo kingslay/FFmpegKit`: **zero releases**. Tags param em `6.1.4`; `main` ainda é `c32be9b` (o commit pinado, FFmpeg n6.1, último commit 2026-04-13). Nada de FFmpeg 8 público.

### 2. mpvkit/ffmpeg-build (repo dedicado de FFmpeg do MPVKit) — REPROVADO
- Último release: `n7.1` (2024-10-18). FFmpeg 7.1 **não tem** o fix do Atmos no `dec3` (só entrou no n8.0) — descartado.

### 3. arthenica/ffmpeg-kit / tanersener/mobile-ffmpeg — REPROVADOS
- Projeto oficialmente aposentado (jan/2025), FFmpeg máximo 6.0, binários em remoção progressiva. Sem FFmpeg 8, sem futuro.

### 4. mpvkit/MPVKit `0.41.0-n8.1.2` (Pre-release, 2026-06-25) — **APROVADO com 1 ressalva**

| # | Requisito | Atende? | Evidência (slices tvOS baixados e inspecionados) |
|---|---|---|---|
| 1 | FFmpeg ≥ 8.0 (fix Atmos `dec3`) | **SIM** | `strings` do Libavformat tvOS: `Lavf62.12.102` — bate exato com `LIBAVFORMAT 62.12.102` da tag `n8.1.2` upstream; release notes confirmam "ffmpeg version: n8.1.2". Os commits do fix (`ebcf2dcb2c42`/`117343c0ba0e`/`17729aa80c61`) estão em n8.0+ |
| 2 | muxer `hls` (`ff_hls_muxer`) | **NÃO** | `FFMPEG_CONFIGURATION` baked: `--disable-muxers` + whitelist **sem** `hls` (mesma lista do kingslay, menos `nut`); `nm -arch arm64`: `_ff_hls_muxer` ausente; muxers definidos: `adts, dash, flac, hevc, latm, m4v, matroska, mov, mp4, mpegts, webm, webm_chunk, webm_dash_manifest` |
| 3 | encoder `flac` (`ff_flac_encoder`) | **SIM** | `--enable-encoder=flac`; `nm` do Libavcodec tvOS: `S _ff_flac_encoder` (e `_ff_truehd_decoder`, `_ff_dca_decoder`, `_ff_eac3_decoder` — a rota TrueHD/DTS→FLAC completa) |
| 4 | slices tvOS + tvsimulator | **SIM** | `tvos-arm64_arm64e` (fat arm64+arm64e via `lipo -info`, paridade com o kingslay) + `tvos-arm64_x86_64-simulator`; bônus: ios, macos, maccatalyst, xros |
| 5 | rede TLS (https) | **SIM** | `--enable-gnutls`; `nm`: `S _ff_tls_protocol`, `T _ff_gnutls_init` — backend gnutls 3.8.11 |
| 6 | layout de módulos compatível | **SIM** | Zip `Libavformat-GPL.xcframework.zip` contém `Libavformat.xcframework/.../Libavformat.framework` com `framework module Libavformat [system] { umbrella "." }` — exatamente o que `import Libavcodec/Libavformat/Libavutil/...` do KSPlayer espera. O Libavutil traz inclusive os mesmos headers internos que o kingslay copia (`config.h`, `internal.h`, `intmath.h`, `libm.h`, `thread.h`, `getenv_utf8.h`, `mem_internal.h`, `attributes_internal.h`) — o script de build do MPVKit é fork do do kingslay |
| 7 | licença ok pra uso pessoal | **SIM** (c/ ressalva) | `--enable-gpl --enable-version3`; **ressalva:** o build passa `--enable-nonfree` → `config.h`: `FFMPEG_LICENSE "nonfree and unredistributable"`. Para uso pessoal: irrelevante. Para redistribuir o app na App Store: impeditivo formal |

Extras confirmados por símbolo no slice tvOS: hwaccels VideoToolbox (`h264/hevc/vp9/av1/prores`), `_ff_dovi_rpu_bsf` (útil para [[dv-nativo]]), decoders `dolby_e/sonic/snow/libdav1d/libuavs3d`.
Perdas vs o 6.1.4 shipped do kingslay: decoder `libzvbi_teletext` (sem libzvbi), protocolo `srt` (sem libsrt), muxer `nut` — nada disso é usado pelo StreamHub.

## O que muda para o [[proavplayer]]

- **Atmos (`dec3`)**: resolvido — movenc do n8.1.2 escreve `flag_eac3_extension_type_a` + `complexity_index_type_a`.
- **Transcode TrueHD/DTS→FLAC**: resolvido — encoder + decoders presentes.
- **Segmentação HLS**: muxer `hls` segue ausente. Três rotas, em ordem de custo:
  1. **m3u8 manual em Swift** sobre fragmentos fMP4 do muxer `mov`/`mp4` (rota 2 do spike) — zero build, e agora sem o bloqueio Atmos que a invalidava como solução completa.
  2. **PR ao MPVKit** adicionando `--enable-muxer=hls` na whitelist (em `Sources/BuildScripts/BuildFFMPEG.swift` do MPVKit) — eles já fizeram builds custom por demanda (ex.: release `0.39.0-hls`, patch de seek de HLS).
  3. **Build do dono** (plano original em [ffmpeg-8x-plano-de-fork.md](ffmpeg-8x-plano-de-fork.md)) — único caminho 100% sob nosso controle.

## Plano de adoção (modelo recomendado: fork do FFmpegKit com binaryTargets `url:`)

A ideia: manter o pacote `FFmpegKit` (products, target shim `FFmpegKit` — que é um `.c` de 1 byte, então `import FFmpegKit` do KSPlayer continua funcionando) e trocar **binários + irmãs** pelos assets do MPVKit.

1. **Fork** `joaoalvess/FFmpegKit` a partir de `kingslay@c32be9b` — sem rodar o plugin BuildFFmpeg.
2. **`Package.swift` do fork** — trocar os 7 binaryTargets `Libav*` de `path:` para `url:` + `checksum` (variantes **GPL**; checksums copiados do `Package.swift` do MPVKit na tag, batem com os assets `*.checksum.txt` do release; revalidar com `swift package compute-checksum` após baixar):

| Target | URL (`https://github.com/mpvkit/MPVKit/releases/download/0.41.0-n8.1.2/`) | checksum |
|---|---|---|
| Libavcodec | `Libavcodec-GPL.xcframework.zip` | `454a01060c06739a3165bff9230e9e26ca4f2036275ac1891f4fd1244bd7a175` |
| Libavdevice | `Libavdevice-GPL.xcframework.zip` | `f0b1cb660467a9430c38490d57b846503366020a1b99c41289b7f027ad8ef1ea` |
| Libavfilter | `Libavfilter-GPL.xcframework.zip` | `9260023873f6f793cbbb85f8d741ec6d3f6c926288a8cd73e38725d223c76ccb` |
| Libavformat | `Libavformat-GPL.xcframework.zip` | `79c0f966811a85eb986f9e951ca0718a4d00cd12914e328c1682696138e3a059` |
| Libavutil | `Libavutil-GPL.xcframework.zip` | `20d0c6449bf2282f77228bccc47a54ebc641283ac43784113010afba01fa0042` |
| Libswresample | `Libswresample-GPL.xcframework.zip` | `b0c3f77b1c523849aef17f7ba241ddf1724cc1f6ecfd2dcb879764937c60b5da` |
| Libswscale | `Libswscale-GPL.xcframework.zip` | `deed00fb706d7d439289df9475e97524a8cc7b7c074b934d1be2267abcdaa217` |

3. **Bibliotecas irmãs** — o FFmpeg 8 do MPVKit foi linkado contra versões específicas; trocar as existentes e adicionar as novas (todas com release + checksum publicados nos repos `mpvkit/*-build`). Mapa de linkagem provado por símbolos `U` nos binários tvOS: Libavformat→`gnutls_*`+`smbc_*`+`xml*`(sistema); Libavcodec→`dav1d_*`+`cmsC*`(lcms2)+`uavs3d*`; Libavfilter→`pl_*`(libplacebo)+`ass_*`(libass)+`shaderc_*`:

| Target no fork | Substituir por | Release |
|---|---|---|
| gmp, nettle, hogweed, gnutls | `mpvkit/gnutls-build` | `3.8.11` |
| libdav1d | `mpvkit/libdav1d-build` | `1.5.2-xcode` |
| lcms2 | `mpvkit/lcms2-build` | `2.17.0` |
| libplacebo | `mpvkit/libplacebo-build` | `7.360.1` |
| MoltenVK | `mpvkit/moltenvk-build` | `1.4.1` |
| libshaderc_combined | `mpvkit/libshaderc-build` | `2025.5.0` |
| libass, libfreetype, libfribidi, libharfbuzz | `mpvkit/libass-build` | `0.17.5` |
| **Libunibreak (NOVO)** | `mpvkit/libass-build` (dep do libass 0.17.5) | `0.17.5` |
| **Libdovi (NOVO)** | `mpvkit/libdovi-build` (dep do libplacebo 7) | `3.3.2` |
| **Libuavs3d (NOVO)** | `mpvkit/libuavs3d-build` (decoder avs3) | `1.2.1-xcode` |
| libsmbclient | `mpvkit/libsmbclient-build` | `4.15.13-2512` |

   URLs e checksums exatos de todos estão no `Package.swift` do MPVKit na tag `0.41.0-n8.1.2` (bloco `AUTO_GENERATE_TARGETS`). **openssl (Libssl/Libcrypto) NÃO é necessário** — zero refs `SSL_*`/`CRYPTO_*` nos Libav* (TLS é gnutls); o MPVKit o lista por outras razões.
4. **Target `FFmpegKit` do fork** — na lista de dependencies: remover `libsrt`, `libzvbi`, `libfontconfig` e `libbluray` (não linkados pelo FFmpeg do MPVKit); adicionar `Libunibreak`, `Libdovi`, `Libuavs3d`; mover `.linkedLibrary("expat")` de macOS-only para todas as plataformas (o MPVKit linka incondicional).
5. **Nomes de target × nome do xcframework interno**: mismatch é aceito pelo SPM — o próprio MPVKit usa target `Libavcodec-GPL` com `Libavcodec.xcframework` dentro do zip. Manter os nomes do kingslay (`Libavcodec`, `libdav1d`, ...) minimiza o diff; os módulos Clang vêm dos modulemaps dos frameworks, que já se chamam `Libavcodec` etc.
6. Remover do índice os `Sources/*.xcframework` migrados (clone leve) e taggear o fork (ex.: `8.1.2`).
7. **Neste repo (Player)**: `Package.swift:46` → `.package(url: "https://github.com/joaoalvess/FFmpegKit.git", from: "8.1.2")`; `swift package update`; aplicar as 2 correções conhecidas de `avcodec_close` (`Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:82` e `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:74` — seção Impacto do [ffmpeg-8x-plano-de-fork.md](ffmpeg-8x-plano-de-fork.md)).
8. **Aceite (dono)**: compilar tvOS; abrir stream https (gnutls); `avcodec_find_encoder(AV_CODEC_ID_FLAC) != nil` em runtime; `startRecord`→fMP4 com amostra E-AC-3 JOC e `ffprobe -show_data`/`mp4box -diso` mostrando a extensão type_a no `dec3`; matriz [[sample-library]] (HEVC 4K HDR10, DV P8.1, TrueHD, anime ASS 10-bit).

**Modelo alternativo descartado** — depender direto do MPVKit: os products são só `MPVKit`/`MPVKit-GPL`, que arrastam `Libmpv`, `Libbluray`, `Libuchardet`, `Libluajit` (~18 MB+ inúteis) e não existe o módulo shim `FFmpegKit` que 6 arquivos do KSPlayer importam.

## Riscos

1. **Muxer `hls` segue ausente** (único requisito reprovado) — mitigações na seção do proavplayer; nada mais no roadmap depende dele.
2. **`--enable-nonfree`** torna o binário formalmente não-redistribuível — ok para uso pessoal; se um dia houver distribuição, build próprio ou pedir ao MPVKit build sem a flag.
3. **Release é Pre-release** — assets poderiam ser republicados; o checksum pina o conteúdo (falha de resolução no pior caso, nunca binário trocado silenciosamente). Mitigação opcional: espelhar os zips num release do próprio fork.
4. **Acoplamento de versão das irmãs** — não misturar os Libav* novos com as xcframeworks 6.1-era do kingslay (libplacebo 6.338 ≠ 7.360, libass 0.17.1 sem unibreak): usar exatamente o conjunto da tabela.
5. **Quebras de API no KSPlayer** — as 2 de `avcodec_close` são certas; deprecations (`FF_API_CODEC_PROPS`) e pontos de assinatura (swr_convert, avio write const) já mapeados no plano de fork.
6. **Comportamento swscale/decode do 8.x** — igual ao risco do plano de fork; validar com a matriz de amostras antes de fechar o pin.

## Método reproduzível

```fish
gh release list --repo kingslay/FFmpegKit          # vazio
gh release list --repo mpvkit/ffmpeg-build         # para em n7.1
gh release view 0.41.0-n8.1.2 --repo mpvkit/MPVKit --json assets

set BASE https://github.com/mpvkit/MPVKit/releases/download/0.41.0-n8.1.2
/usr/bin/curl -sLO $BASE/Libavformat-GPL.xcframework.zip
unzip -j Libavformat-GPL.xcframework.zip 'Libavformat.xcframework/tvos-arm64_arm64e/*/Libavformat' '*/tvos-arm64_arm64e/*/config.h' -d lavf
rg -o 'FFMPEG_CONFIGURATION "[^"]*"' lavf/config.h | tr ' ' '\n' | rg 'muxer=|gnutls|nonfree'
xcrun nm -arch arm64 lavf/Libavformat | rg '_ff_hls_muxer|_ff_tls_protocol'   # ausente | S
strings lavf/Libavformat | rg -o 'Lavf[0-9.]+'                                # Lavf62.12.102
xcrun lipo -info lavf/Libavformat                                             # arm64 arm64e
# idem Libavcodec-GPL → S _ff_flac_encoder, _ff_dovi_rpu_bsf
```

## Referências

- MPVKit release `0.41.0-n8.1.2`: assets + `Package.swift` da tag (URLs/checksums, targets `_FFmpeg-GPL`), release notes ("ffmpeg version: n8.1.2").
- Binários inspecionados (slices `tvos-arm64_arm64e`): `Libavformat-GPL`, `Libavcodec-GPL`, `Libavfilter-GPL`, `Libavutil-GPL` do release acima.
- FFmpeg upstream: `libavformat/version.h`/`version_major.h` da tag `n8.1.2` (62.12.102).
- `kingslay/FFmpegKit@c32be9b`: `Package.swift` (products/targets/linkerSettings, `Sources/FFmpegKit/FFmpegKit.c` de 1 byte).
- Este repo: `Package.swift:46`, imports FFmpeg em `Sources/KSPlayer/MEPlayer/*` e `Metal/PixelBufferProtocol.swift`.
- Docs: [spike-ffmpegkit-614-resultado.md](spike-ffmpegkit-614-resultado.md), [ffmpeg-8x-plano-de-fork.md](ffmpeg-8x-plano-de-fork.md).
