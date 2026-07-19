# Exec [[ffmpeg-8x]] — adoção dos binários prontos de FFmpeg 8.1.2 (MPVKit 0.41.0-n8.1.2)

**Branch:** `task/ffmpeg8-binarios` (worktree em `/private/tmp/claude-501/-Users-joaoalves-Developer-StreamHub/113db3ca-fa39-47b3-8e07-30a97e5e0f39/scratchpad/wt-ffmpeg8-binarios`, a partir de `1b8b46f`, main intocado)
**Status:** mergeado em `main`; `swift package resolve` + `swift build` (macOS) OK em 2026-07-18 após duas correções de API 6→8 (`872da92` shim sem `AV_CH_LAYOUT_NATIVE`; `5832b58` swscale com `SwsContext` tipado e enum `SwsFlags`). Sanidade dos binários tvOS confirmada: `Lavf62.12.102`, `_ff_flac_encoder` e `_ff_dovi_rpu_bsf` presentes, muxer `hls` ausente (como previsto). Pendente: build tvOS + smoke test em device (dono).
**Plano base:** [ffmpeg-8x-binarios-prontos.md](../roadmap/ffmpeg-8x-binarios-prontos.md) (seção "Plano de adoção") + seção "Impacto no KSPlayer" de [ffmpeg-8x-plano-de-fork.md](../roadmap/ffmpeg-8x-plano-de-fork.md)

## Commits

| Hash | Mensagem |
|---|---|
| `bed7ae9` | feat: vendor FFmpegKit package backed by MPVKit 0.41.0-n8.1.2 binaries |
| `5aa2d75` | feat: point KSPlayer at vendored FFmpegKit package |
| `8d07f06` | fix: drop avcodec_close calls removed in ffmpeg 8 |

## O que foi feito

1. **Package FFmpegKit vendorizado localmente** em `FFmpegKit/` na raiz do repo (sem fork público, sem push — modelo do plano adaptado: em vez de `joaoalvess/FFmpegKit` no GitHub, package local consumido por `.package(path: "FFmpegKit")`). Estrutura:
   - `FFmpegKit/Package.swift` — mesmo contrato do kingslay (products `FFmpegKit`, `Libav*`, `gmp/nettle/hogweed/gnutls`, `libass`; target shim `FFmpegKit`), com os binaryTargets trocados de `path:` para `url:`+`checksum` apontando para os releases do MPVKit (tabela abaixo).
   - `FFmpegKit/Sources/FFmpegKit/` — shim copiado **verbatim** do `kingslay/FFmpegKit@c32be9b` (o `FFmpegKit.c` de 1 byte + os 7 headers `include/*_shim.h` com `swift_AV_CH_LAYOUT_*`, `swift_AVERROR*`, `ff_isom_write_vpcc`, `URLContext`), extraído do cache SPM local (`~/Library/Caches/org.swift.swiftpm/repositories/FFmpegKit-0bc1979b`).
   - Removidos vs upstream kingslay: products/targets `libmpv`, executáveis `ffmpeg/ffplay/ffprobe`, `fftools`, `SDL2`, plugin `BuildFFmpeg`; e os binaryTargets órfãos `libsrt`, `libzvbi`, `libfontconfig`, `libbluray` (não linkados pelo FFmpeg do MPVKit).
   - Adicionados (novas deps do conjunto 8.x): `Libunibreak` (dep do libass 0.17.5, incluída também no product `libass`), `Libdovi` (dep do libplacebo 7), `Libuavs3d` (decoder avs3). `.linkedLibrary("expat")` movida de macOS-only para incondicional (paridade com MPVKit). openssl NÃO incluído (TLS é gnutls; zero refs `SSL_*` nos Libav*).
   - `.gitignore` raiz: removida a entry legada `FFmpegKit` (ignorava qualquer diretório com esse nome e bloqueava o vendoring).
2. **`Package.swift` raiz** — `.package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.4")` → `.package(path: "FFmpegKit")`. O product/módulo `FFmpegKit` continua com o mesmo nome, então os `import FFmpegKit`/`import Libav*` dos 15 arquivos do KSPlayer não mudam. `Package.resolved` deletado (única pin era o kingslay; dependência local não gera pin — SPM regenera o arquivo se necessário).
3. **Correções de API 6→8** (as 2 quebras duras da seção "Impacto no KSPlayer"; `avcodec_close` foi removida no FFmpeg 8.0):
   - `Sources/KSPlayer/MEPlayer/SubtitleDecode.swift:83-86` — removido `avcodec_close(codecContext)`; o `if let codecContext` virou `if codecContext != nil` (o binding ficaria sem uso) e o `avcodec_free_context(&self.codecContext)` segue fazendo o teardown completo.
   - `Sources/KSPlayer/MEPlayer/ThumbnailController.swift:74` — removida a linha `avcodec_close(codecContext)` do `defer`; o `avcodec_free_context` logo abaixo cobre.
   - Nada mais foi tocado: deprecation `FF_API_CODEC_PROPS` (`FFmpegDecode.swift:43`) compila com warning no 8.x (fix futuro mapeado no plano); `swr_convert`/`avio_alloc_context`/`withMemoryRebound` do DOVI conferidos como compatíveis sem edição.

## Tabela binário → URL → checksum aplicada

FFmpeg (variantes **GPL**, release `mpvkit/MPVKit 0.41.0-n8.1.2`, base `https://github.com/mpvkit/MPVKit/releases/download/0.41.0-n8.1.2/`):

| Target | Asset | Checksum |
|---|---|---|
| Libavcodec | `Libavcodec-GPL.xcframework.zip` | `454a01060c06739a3165bff9230e9e26ca4f2036275ac1891f4fd1244bd7a175` |
| Libavdevice | `Libavdevice-GPL.xcframework.zip` | `f0b1cb660467a9430c38490d57b846503366020a1b99c41289b7f027ad8ef1ea` |
| Libavfilter | `Libavfilter-GPL.xcframework.zip` | `9260023873f6f793cbbb85f8d741ec6d3f6c926288a8cd73e38725d223c76ccb` |
| Libavformat | `Libavformat-GPL.xcframework.zip` | `79c0f966811a85eb986f9e951ca0718a4d00cd12914e328c1682696138e3a059` |
| Libavutil | `Libavutil-GPL.xcframework.zip` | `20d0c6449bf2282f77228bccc47a54ebc641283ac43784113010afba01fa0042` |
| Libswresample | `Libswresample-GPL.xcframework.zip` | `b0c3f77b1c523849aef17f7ba241ddf1724cc1f6ecfd2dcb879764937c60b5da` |
| Libswscale | `Libswscale-GPL.xcframework.zip` | `deed00fb706d7d439289df9475e97524a8cc7b7c074b934d1be2267abcdaa217` |

Irmãs (repos `mpvkit/*-build`, checksums copiados do `Package.swift` do MPVKit na tag — bloco `AUTO_GENERATE_TARGETS`):

| Target | Release/Asset | Checksum |
|---|---|---|
| gmp | `gnutls-build/3.8.11/gmp.xcframework.zip` | `ad33c7a08f4cdcb9924c8f0e6d9a054dad33d7794b97667bf8b6fb2b236ae585` |
| nettle | `gnutls-build/3.8.11/nettle.xcframework.zip` | `0fdf3ebf8bd7b8bc8eee837cf27261cb4c52ae520b6576a2f468656aa1691e02` |
| hogweed | `gnutls-build/3.8.11/hogweed.xcframework.zip` | `25727c9fa67287fa0a4f4722f88bb8be669b23cd7e837e2d00870eb8a25d3f27` |
| gnutls | `gnutls-build/3.8.11/gnutls.xcframework.zip` | `3dbec5809339189bf9679e218c6cff387ebf8fb72745927835afc2678f5c9f4d` |
| libdav1d | `libdav1d-build/1.5.2-xcode/Libdav1d.xcframework.zip` | `8a8b78e23e28ecc213232805f3c1936141fc9befe113e87234f4f897f430a532` |
| lcms2 | `lcms2-build/2.17.0/lcms2.xcframework.zip` | `dc0dce0606f6ab6841a8ec5a6bd4448e2f3ef00661a050460f806c9393dc6982` |
| libplacebo | `libplacebo-build/7.360.1/Libplacebo.xcframework.zip` | `2fa3d54cb81f302d6f11c7b2f509af30944381c3b11ee9d35096eb4637a6e2dd` |
| MoltenVK | `moltenvk-build/1.4.1/MoltenVK.xcframework.zip` | `9bd1ca1e4563bacd25d6e55d37b10341d50b2601bc2684bc332188e79daa2b79` |
| libshaderc_combined | `libshaderc-build/2025.5.0/Libshaderc_combined.xcframework.zip` | `758047b615708575b580eb960a2d083f760a29dc462d6eaa360416c946ce433b` |
| libfreetype | `libass-build/0.17.5/Libfreetype.xcframework.zip` | `496ca62488530e14b1e4624d20ee2b237c0bd675cd70c19da578a5768302d02d` |
| libfribidi | `libass-build/0.17.5/Libfribidi.xcframework.zip` | `bc15e097b892f2f90424e4a27ba287070cc2f98a74a4da10e6d2481d15cf5ff9` |
| libharfbuzz | `libass-build/0.17.5/Libharfbuzz.xcframework.zip` | `aa8e0b9ca0387dac74e3e93c86e34d11982bb013b28022d0e6966a8427a35b2e` |
| Libunibreak (novo) | `libass-build/0.17.5/Libunibreak.xcframework.zip` | `940d9833cf4477d0a260d9f2b4066125bc0ff7bbc111ac3c90e774765b77a559` |
| libass | `libass-build/0.17.5/Libass.xcframework.zip` | `3f4c576d2818ceb4544aa2a20e1f55846511c5e706fd19adc3ea9fd842270498` |
| Libdovi (novo) | `libdovi-build/3.3.2/Libdovi.xcframework.zip` | `e693e239808350868e79c5448ef9f02e2716bc822dd8632a41a368a1eae5ca7d` |
| Libuavs3d (novo) | `libuavs3d-build/1.2.1-xcode/Libuavs3d.xcframework.zip` | `1e69250279be9334cd2f6849abdc884c8e4bb29212467b6f071fdc1ac2010b6b` |
| libsmbclient | `libsmbclient-build/4.15.13-2512/Libsmbclient.xcframework.zip` | `3a53375fab11bc888cc553664ea5dd902208d04f0cc21ec746302bf356246b6f` |

## Verificações feitas (sem build)

- `swift package dump-package` OK no package vendorizado e no raiz (parse de manifesto apenas, sem resolução/download).
- Checksums conferidos 1:1 contra o `Package.swift` do MPVKit na tag `0.41.0-n8.1.2` — batem com a tabela do plano.
- `xcrun nm` no slice `tvos-arm64_arm64e` do `Libavformat-GPL` real (zip baixado e descartado): `_ff_isom_write_vpcc` **definido** (`T`) — é o único símbolo interno que o shim declara E o KSPlayer chama (`FFmpegAssetTrack.swift:202`); link fecha.
- `ffurl_context_class` sumiu do Libavformat 8.x, mas no shim é só um `extern` sem nenhum uso no KSPlayer — não gera referência de link. Se um dia for usado, remover do `avformat_shim.h`.
- Zero `avcodec_close` restantes em `Sources/`; nenhum outro símbolo removido no 8.x em uso (varredura da seção Impacto do plano de fork).

## Pendências / avisos

- **⚠️ Disco: o primeiro resolve/build baixa ~1-2 GB de xcframeworks (25 binaryTargets) e o Mac está com ~3 GB livres.** Liberar espaço antes (candidatos: DerivedData antiga, caches SPM de outros projetos) ou o download/unzip vai falhar no meio.
- Muxer `hls` segue ausente (única ressalva do plano) — rota do proavplayer continua sendo playlist m3u8 manual sobre fMP4 do muxer `mov`, ou PR ao MPVKit.
- Binários com `--enable-nonfree` (`FFMPEG_LICENSE "nonfree and unredistributable"`): ok para uso pessoal, impeditivo para distribuição em loja.
- Release do MPVKit é Pre-release; checksums pinam o conteúdo (pior caso: falha de resolução, nunca binário trocado). Mitigação futura opcional: espelhar os zips.
- Perdas vs 6.1.4: decoder `libzvbi_teletext`, protocolo `srt`, muxer `nut` — nada usado pelo StreamHub.
- `FF_API_CODEC_PROPS` (`FFmpegDecode.swift:43`) vira quebra dura no FFmpeg 9 — fix futuro: detectar CC via side data A53.
- `Demo/` (CocoaPods + workspace próprio) ainda referencia kingslay — não é consumido pelo StreamHub; migrar só se for usar o demo.
- Docs a atualizar após aceite (regra 2 do ROADMAP): `README.md:64`, `docs/00-ARQUITETURA.md`, `docs/01-vis-o-geral-e-build.md`, roadmap ffmpeg-8x + `ffmpeg-version-bundled.md`.
- Branch `task/ffmpeg8-binarios` só existe no worktree local — merge em main é decisão do dono após validação.

## Checklist de validação (dono)

1. `cd` no worktree (ou merge da branch) e resolver packages: abrir no Xcode ou `swift package resolve` — espera-se download dos 25 zips do GitHub (~1-2 GB; conferir espaço em disco antes).
2. Buildar o Player para tvOS (e as demais plataformas usadas). Esperado: compila sem erro; warning de deprecation em `FFmpegDecode.swift:43` é normal.
3. Sanidade dos binários resolvidos (30 s):
   - `strings <Libavformat tvOS> | rg -o 'Lavf62'` → série 8.x;
   - `xcrun nm -arch arm64 <Libavcodec tvOS> | rg '_ff_flac_encoder|_ff_dovi_rpu_bsf'` → definidos.
4. Smoke test de playback **HTTPS** (gnutls): abrir um stream `https` de debrid no app — se abrir, TLS do novo gnutls 3.8.11 está ok.
5. Encoder FLAC em runtime: `avcodec_find_encoder(AV_CODEC_ID_FLAC) != nil`.
6. Aceite completo (quando for fechar o pin): `startRecord`→fMP4 com amostra E-AC-3 JOC e `ffprobe -show_data`/`mp4box -diso` mostrando `flag_eac3_extension_type_a`+`complexity_index_type_a` no `dec3`; matriz [[sample-library]] (HEVC 4K HDR10, DV P8.1, TrueHD, anime ASS 10-bit).
