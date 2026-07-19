# Resultado do spike [[spike-ffmpegkit-614]] — capacidades do binário FFmpegKit 6.1.4

**Data:** 2026-07-18 · **Método:** análise estática (flags de configure + config baked no binário + símbolos via `nm`) + histórico do FFmpeg upstream. Sem build no device.

## TL;DR

| Pergunta | Resposta | Evidência decisiva |
|---|---|---|
| (a) Muxer `hls` habilitado? | **NÃO** | `--disable-muxers` sem `--enable-muxer=hls`; símbolo `_ff_hls_muxer` ausente do binário tvOS |
| (b) Encoder `flac` habilitado? | **SIM** | `--enable-encoder=flac`; símbolo `_ff_flac_encoder` definido no binário tvOS |
| (c) Remux E-AC-3 JOC preserva `complexity_index_type_a` no `dec3`? | **NÃO** | `mov_write_eac3_tag` do FFmpeg n6.1 não escreve a extensão type_a; fix só entrou no FFmpeg 8.0 (jun/2025) |

**Consequência para o roadmap:** o spike **refuta** o suporte do 6.1.4 ao remux completo do [[proavplayer]] em duas frentes (segmentação HLS via muxer `hls` e sinalização Atmos no `dec3`). [[ffmpeg-8x]] deixa de ser "alinhamento de versão" e vira **pré-requisito técnico duplo** — e o fork deve **adicionar `--enable-muxer=hls`** às flags de configure no mesmo rebuild. A única peça do [[proavplayer]] que o 6.1.4 já sustenta é o transcode TrueHD/DTS→FLAC (encoder presente).

## Pin analisado

- `Package.resolved` deste repo: `kingslay/FFmpegKit` @ revision `c32be9bfb628042737ad3ef622e930c5c7b15954`, version `6.1.4` (commit "Merge pull request #45 from superuser404notfound/main").
- FFmpeg interno pinado em `Plugins/BuildFFmpeg/main.swift:150` → `"n6.1"` (tag do mirror `FFmpeg/FFmpeg`).
- Binário shipped confirma a série: strings do Libavformat tvOS contêm `Lavf60.16.100` (libavformat 60.16 = FFmpeg 6.1.x).
- Os `binaryTarget` do `Package.swift` do FFmpegKit são **`path:`-based** (`Sources/*.xcframework` commitados no próprio repo) — não há zips em GitHub Releases; a prova por símbolos foi feita sobre os blobs commitados na revision pinada.

## (a) Muxer `hls` — NÃO habilitado

**Camada 1 — script de build** (`Plugins/BuildFFmpeg/BuildFFMPEG.swift:286-291`, revision pinada):

```
"--disable-muxers",
"--enable-muxer=flac", "--enable-muxer=dash", "--enable-muxer=hevc",
"--enable-muxer=m4v", "--enable-muxer=matroska", "--enable-muxer=mov", "--enable-muxer=mp4",
"--enable-muxer=mpegts", "--enable-muxer=webm*",
"--enable-muxer=nut",
```

`hls` não está na lista (nem `segment`). O `--enable-demuxer=hls` da linha 307 é só **leitura** de HLS, não escrita.

**Camada 2 — configure baked no binário shipped**: o header `Sources/Libavformat.xcframework/tvos-arm64_arm64e/Libavformat.framework/Headers/config.h` embute a string `FFMPEG_CONFIGURATION` exata com que o binário commitado foi compilado — mesma lista: `--disable-muxers ... --enable-muxer=flac --enable-muxer=dash --enable-muxer=hevc --enable-muxer=m4v --enable-muxer=matroska --enable-muxer=mov --enable-muxer=mp4 --enable-muxer=mpegts --enable-muxer='webm*' --enable-muxer=nut`, sem `hls`.

**Camada 3 — símbolos (prova definitiva)**: `nm -arch arm64` sobre `Sources/Libavformat.xcframework/tvos-arm64_arm64e/Libavformat.framework/Libavformat` (static archive universal arm64/arm64e):

- `_ff_hls_muxer`: **ausente** (zero hits, inclusive para objetos `hlsenc`).
- `_ff_hls_demuxer`: presente (leitura de HLS funciona).
- Muxers **definidos** no binário tvOS: `adts, dash, flac, hevc, latm, m4v, matroska, mov, mp4, mpegts, nut, webm, webm_chunk, webm_dash_manifest`.

**Nuance importante para o [[proavplayer]]:** o muxer `mov`/`mp4` **está presente** — `startRecord`→fMP4 (inclusive fMP4 fragmentado via `movflags`) funciona hoje. O que falta é a peça que gera playlist `.m3u8` + rotação de segmentos (o muxer `hls`). Rotas possíveis: (1) habilitar `--enable-muxer=hls` no rebuild do fork [[ffmpeg-8x]] (custo ~zero, os muxers `mpegts`/`mov` dos segmentos já estão lá) — rota recomendada; (2) escrever a playlist m3u8 manualmente em Swift sobre fragmentos do muxer `mp4` atual — desbloquearia um MVP de remux **sem** esperar o fork, mas sem resolver o Atmos (item c).

## (b) Encoder `flac` — SIM, habilitado

**Camada 1 — script** (`BuildFFMPEG.swift:293-295`):

```
"--disable-encoders",
"--enable-encoder=aac", "--enable-encoder=alac", "--enable-encoder=flac", "--enable-encoder=pcm*",
"--enable-encoder=movtext", "--enable-encoder=mpeg4", "--enable-encoder=prores",
```

**Camada 2 — configure baked** no binário tvOS: `--disable-encoders ... --enable-encoder=flac ...` presente na `FFMPEG_CONFIGURATION`.

**Camada 3 — símbolos**: `nm -arch arm64` sobre `Sources/Libavcodec.xcframework/tvos-arm64_arm64e/Libavcodec.framework/Libavcodec`:

- `_ff_flac_encoder`: **definido** (símbolo `S`), além de `_ff_flac_decoder`, `_ff_aac_encoder`, `_ff_alac_encoder`.
- O muxer `flac` também está no Libavformat, e o muxer `mp4`/`mov` aceita FLAC — a rota TrueHD/DTS→FLAC lossless do [[proavplayer]] **é viável já no 6.1.4**.

Divergência menor registrada: a `FFMPEG_CONFIGURATION` do binário tvOS shipped inclui `--enable-encoder=h264_videotoolbox --enable-encoder=hevc_videotoolbox --enable-encoder=prores_videotoolbox` e `--disable-avdevice`, enquanto o `BuildFFMPEG.swift` da revision pinada só adiciona esses encoders no branch watchOS/Android — o binário commitado foi gerado por um estado ligeiramente diferente do script. As duas fontes **concordam** nos três pontos deste spike.

## (c) `complexity_index_type_a` no `dec3` — NÃO preservado no 6.1.4; fix é FFmpeg 8.0+

O átomo `dec3` (EC3SpecificBox) é escrito por `mov_write_eac3_tag` em `libavformat/movenc.c` (usado pelo muxer `mp4`/`mov` e, via fMP4, pelo muxer `hls`). O sinal Atmos/JOC é o par `flag_eac3_extension_type_a` + `complexity_index_type_a` no fim do box — é isso que o AVPlayer/tvOS usa para acender o Atmos.

- **FFmpeg n6.1/n6.1.4** (`movenc.c:570`, `mov_write_eac3_tag`): o writer termina em `num_dep_sub`/`chan_loc` e **não escreve nenhum campo de extensão type_a**. A string `complexity_index` não existe em `movenc.c` nem em `libavcodec/ac3_parser_internal.h` (o parser nem extrai o campo do bitstream). Remux E-AC-3 JOC → fMP4 no 6.1.4 produz `dec3` **sem** a sinalização Atmos: o áudio toca como E-AC-3 5.1 comum.
- **Fix upstream** (todos em jun/2025 — a crença "pós-abr/2025" do roadmap estava certa na direção, a data exata é jun/2025):
  - `ebcf2dcb2c424da7084b18832043529c3dd62e0f` — *"avformat/movenc: handle EAC-3 extension bits for Atmos"* (2025-06-03, autor nyanmisaka, fixes trac #9996) — adiciona `complexity_index_type_a` ao `struct eac3_info` e escreve `flag_eac3_extension_type_a` + `complexity_index_type_a` no `dec3`.
  - `117343c0ba0e` — *"avcodec/ac3_parser: handle more header bits in ff_ac3_parse_header()"* (2025-06-05) — lado do parser: expõe `eac3_extension_type_a`/`complexity_index_type_a` (`ac3_parser_internal.h:80-81` em n8.0).
  - `17729aa80c61` — *"avformat/movenc: fix writing reserved bits in EC3SpecificBox"* (2025-06-05) — correção complementar do box.
- **Primeira release com o fix: FFmpeg 8.0** (tag `n8.0`, 2025-08-21). Confirmado por grep no código das tags: presente em `n8.0` (`movenc.c:400,482,611,636-639`); **ausente** em `n6.1`, `n6.1.4`, `n7.1`, `n7.1.2` e `n7.1.3` (não foi backportado — é feature, não bugfix de segurança).

**Conclusão:** a metade Atmos do [[proavplayer]] depende de FFmpeg ≥ 8.0 → confirma [[ffmpeg-8x]] (alvo `n8.1.x`) como pré-requisito técnico real, agora com dupla justificativa (dec3 Atmos + muxer hls).

## Método reproduzível

```fish
# 1. Pin
cat Package.resolved   # revision c32be9bf..., version 6.1.4

# 2. Clone parcial do FFmpegKit sem baixar os xcframeworks multi-GB
git clone --filter=blob:none --no-checkout https://github.com/kingslay/FFmpegKit ffmpegkit-pinned
cd ffmpegkit-pinned
git sparse-checkout init --cone
git sparse-checkout set Plugins
git checkout c32be9bfb628042737ad3ef622e930c5c7b15954
rg -n "muxer|encoder" Plugins/BuildFFmpeg/BuildFFMPEG.swift   # flags de configure

# 3. Configure baked no binário shipped (sem baixar o binário)
git ls-tree -r HEAD Sources/Libavformat.xcframework | rg tvos-arm64_arm64e
git cat-file -p <blob-do-config.h> | rg FFMPEG_CONFIGURATION

# 4. Prova por símbolos — baixa só os slices tvOS
git sparse-checkout add Sources/Libavformat.xcframework/tvos-arm64_arm64e \
                        Sources/Libavcodec.xcframework/tvos-arm64_arm64e
xcrun nm -arch arm64 Sources/Libavformat.xcframework/tvos-arm64_arm64e/Libavformat.framework/Libavformat | rg "_muxer"
xcrun nm -arch arm64 Sources/Libavcodec.xcframework/tvos-arm64_arm64e/Libavcodec.framework/Libavcodec | rg "flac_(encoder|decoder)"

# 5. Histórico do dec3 upstream
curl -sL https://raw.githubusercontent.com/FFmpeg/FFmpeg/n6.1.4/libavformat/movenc.c | rg -c complexity_index   # 0
curl -sL https://raw.githubusercontent.com/FFmpeg/FFmpeg/n8.0/libavformat/movenc.c   | rg -n complexity_index   # presente
gh api repos/FFmpeg/FFmpeg/commits/ebcf2dcb2c42   # commit do fix, 2025-06-03
```

## Validação comportamental no device (opcional, dono)

A conclusão acima é estática e considerada suficiente para ordenar o roadmap. Como confirmação opcional, o dono pode rodar o harness mínimo sobre `MEPlayerItem.startRecord`→fMP4 com uma amostra E-AC-3 JOC ([[sample-library]]) e inspecionar o `dec3` de saída (`ffprobe -show_data` ou `mp4box -diso`): a expectativa é o box terminar sem os bytes da extensão type_a. O resultado esperado do encoder FLAC também pode ser confirmado com `avcodec_find_encoder(AV_CODEC_ID_FLAC) != nil` em runtime.

## Referências

- `Package.resolved` (este repo) — pin `6.1.4` / `c32be9bfb628042737ad3ef622e930c5c7b15954`.
- `kingslay/FFmpegKit` @ `c32be9b`: `Plugins/BuildFFmpeg/BuildFFMPEG.swift:286-295` (flags de muxers/encoders), `Plugins/BuildFFmpeg/main.swift:150` (`n6.1`), `Package.swift:135-236` (binaryTargets `path:`-based).
- Binários analisados (blobs da revision pinada): `Sources/Libavformat.xcframework/tvos-arm64_arm64e/` e `Sources/Libavcodec.xcframework/tvos-arm64_arm64e/`.
- FFmpeg upstream: `libavformat/movenc.c` nas tags `n6.1.4`/`n7.1.x` (sem fix) e `n8.0` (com fix); commits `ebcf2dcb2c42`, `117343c0ba0e`, `17729aa80c61`; trac ticket #9996; tag `n8.0` em 2025-08-21.
- Docs relacionados: [ffmpeg-version-bundled.md](ffmpeg-version-bundled.md), [proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md](proavplayer-mkv-com-dolby-vision-e-atmos-nativos-via-avplaye.md).
