## Status

Parcial (corrigido pela verificação adversarial — ver seção "Verificação").

## Evidência

- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:93` — `avcodec_find_decoder(codecContext.pointee.codec_id)`: busca genérica de decoder pelo `codec_id` retornado pelo demuxer, sem whitelist/restrição de formato no código do player.
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:80-119` — `AVCodecParameters.createContext(options:)`: fluxo completo de criação/abertura de contexto de decodificação (`avcodec_parameters_to_context` → `avcodec_find_decoder` → `avcodec_open2`), aplicado a qualquer stream que o demuxer do FFmpeg reconheça.
- `Sources/KSPlayer/MEPlayer/AVFFmpegExtension.swift:329-380` — switch de `AV_CODEC_ID_*` para mapear `codec_id` em `AVFileType`/mimetype de exibição (H263, H264, HEVC, MPEG1/2/4, VP9, AAC, AC3, ADPCM, ALAC, AMR, EAC3, GSM, iLBC, MP1/2/3, PCM A-law/µ-law, QDMC/QDM2, etc.) — usado apenas para metadados/UI, não limita quais codecs podem ser decodificados.
- `Sources/KSPlayer/MEPlayer/MEPlayerItem.swift` (em torno da l.383-406) — abertura de input via `avformat_open_input`/enumeração de streams do formato inteiro, sem filtro de container.
- `Sources/KSPlayer/MEPlayer/VideoToolboxDecode.swift` e `AVFFmpegExtension.swift:19-55` (`getFormat()`, `AV_HWDEVICE_TYPE_VIDEOTOOLBOX`) — caminho de decodificação por hardware (VideoToolbox) coexiste com o fallback puro-software do FFmpeg; quando HW falha ou está desabilitado, cai para o decoder software do próprio FFmpeg (mesmo `avcodec_find_decoder`).
- `Package.swift:24,46` — dependência declarada: `.package(url: "https://github.com/kingslay/FFmpegKit.git", from: "6.1.4")`, fornecendo `Libavcodec`/`Libavformat`/`Libavfilter` como binários pré-compilados; `Libass`/`Libmpv` comentados (não usados).

## Como funciona

O KSMEPlayer (GPL) não implementa nenhuma lista de formatos suportados/bloqueados no próprio código Swift: ele delega 100% da demuxagem e decodificação ao FFmpeg via o pacote `FFmpegKit` (binário pré-buildado, versão 6.1.4). O fluxo é:

1. `MEPlayerItem` abre o arquivo/stream com as APIs de `Libavformat` (`avformat_open_input` e correlatos), que reconhece qualquer container para o qual o FFmpeg tenha um demuxer compilado.
2. Para cada stream, `AVCodecParameters.createContext(options:)` (`AVFFmpegExtension.swift:80`) chama `avcodec_find_decoder(codec_id)` — uma busca genérica na tabela de decoders registrados no binário do FFmpeg, sem qualquer filtro por tipo de codec no código do player.
3. Se `options.hardwareDecode` estiver ativo e o codec for vídeo, tenta primeiro o caminho VideoToolbox (`getFormat()` registra o hw_device_ctx); caso contrário (ou em fallback), usa o decoder software padrão do FFmpeg — ambos passam pelo mesmo `avcodec_open2`.

Ou seja, "suportar todos os formatos de demux/decode" é uma propriedade herdada do build do FFmpeg vinculado, não uma feature de código exclusiva do produto pago recriada aqui — e o player GPL já se comporta dessa forma por arquitetura (não há nenhum gate comercial no código Swift que restrinja isso).

## O que falta

Nada a implementar no código Swift em si — a arquitetura já é "aberta" (qualquer decoder que o FFmpeg linkado exponha é usável). A única variável real é **quais formatos o binário do FFmpegKit 6.1.4 (kingslay) foi de fato compilado com suporte** (ex.: codecs proprietários como DTS/TrueHD, certos formatos de imagem/legenda, ou decoders opcionais desabilitados por licença/tamanho no build). Isso não foi possível confirmar nesta investigação porque o binário compilado do `FFmpegKit` não está vendorizado neste repositório (é resolvido via SPM a partir do repo externo `kingslay/FFmpegKit`); não há `config.h` local do FFmpeg nem scripts de build de FFmpeg neste projeto para inspecionar as flags `--enable-decoder=...`/`--enable-demuxer=...` usadas.

Para fechar essa lacuna, os próximos passos seriam:
- Inspecionar o repositório `kingslay/FFmpegKit` (tag 6.1.4) e seu script/spec de build para ver a lista de `--enable-decoder`/`--enable-demuxer`/`--enable-parser` habilitados no `configure` do FFmpeg.
- Ou, em runtime, chamar `av_codec_iterate`/`av_demuxer_iterate` a partir do app e logar a lista real de decoders/demuxers presentes no binário linkado, comparando com a lista completa do FFmpeg upstream.

## Verificação

**Veredito: conclusão anterior REFUTADA. Status corrigido de "Presente" para "Parcial". A tabela oficial (❌ para o GPL) está correta.**

A investigação anterior acertou na análise do código Swift — de fato não há whitelist, gate comercial ou código condicional restringindo formatos em `Sources/KSPlayer` (isso foi re-verificado: buscas por license/premium/whitelist/unsupported não retornam nenhum gate; `FFmpegAssetTrack.init?` só retorna `nil` para streams que não sejam audio/video/subtitle; `createContext` usa `avcodec_find_decoder` genérico). Porém, ela parou exatamente na "única incerteza real" que ela mesma apontou — e é ali que a feature deixa de existir:

- O `Package.resolved` pina `kingslay/FFmpegKit` na tag `6.1.4` (revision `c32be9bfb628042737ad3ef622e930c5c7b15954`), cujos `binaryTarget` apontam para xcframeworks pré-compilados commitados no próprio repo (`Sources/Libavcodec.xcframework` etc.).
- O script que gera esses binários (`Plugins/BuildFFmpeg/BuildFFMPEG.swift` na tag `6.1.4` do repo `kingslay/FFmpegKit`, array `ffmpegConfiguers`) configura o FFmpeg com **`--disable-demuxers`** (l.300) e **`--disable-decoders`** (l.317), reabilitando apenas uma whitelist curta:
  - ~35 demuxers (`aac, ac3, aiff, amr, ape, asf, ass, av1, avi, caf, concat, dash, data, dv, eac3, flac, flv, h264, hevc, hls, live_flv, loas, m4v, matroska, mov, mp3, mpeg*, nut, ogg, rm, rtsp, rtp, srt, vc1, wav, webm_dash_manifest`);
  - decoders de vídeo/áudio/legenda selecionados (h264, hevc, vp6-9, av1, mpeg*, prores, rv*, wmv*, aac*, ac3*, eac3*, dca, truehd, flac, opus, vorbis, pcm*, wma*, ass/ssa/subrip, pgssub, dvdsub, movtext, webvtt etc.).
  - Também: `--disable-muxers`/`--disable-encoders`/`--disable-filters` com whitelists (só `--enable-protocols` e `--enable-bsfs` são integrais).
- O próprio script documenta a motivação (comentários nas l.299 e l.316): com todos os demuxers o `libavformat` iria de 4MB para 8MB, e com todos os decoders o `libavcodec` iria de 20MB para 40MB.
- Exemplos concretos de formatos que o binário GPL 6.1.4 **não** suporta: containers MXF, image2/GIF/APNG, WavPack (`wv`), Musepack, DSF/DFF, TAK, Shorten; decoders de vídeo Theora, DV video (`dvvideo` — o demuxer `dv` está habilitado, mas o decoder não), DNxHD, CineForm (`cfhd`), Ut Video, MagicYUV, Cinepak, `msmpeg4v1/v2/v3` (DivX 3 em AVIs antigos), VP3/VP5, PNG/GIF/WebP/TIFF/JPEG2000; áudio Speex, WavPack, ATRAC, Nellymoser, GSM, iLBC, QDM2, RealAudio antigos (`ra_144/ra_288/sipr` — o demuxer `rm` abre mas essas trilhas não decodificam); legendas SAMI, MicroDVD, SubViewer, RealText, STL, JACOsub.
- Comportamento em runtime no player: container fora da whitelist → `avformat_open_input` falha (`.formatOpenInput`); container ok mas codec fora da whitelist → `avcodec_find_decoder` retorna `nil` e `createContext` lança `.codecContextFindDecoder` (`AVFFmpegExtension.swift:93-96`) quando a decodificação inicia. O caminho `VideoToolboxDecode` não contorna isso na prática: os codecs que o VideoToolbox aceita já estão todos na whitelist, e o fallback dele é justamente `FFmpegDecode` (`MEPlayerItemTrack.swift:160-162`).
- A linha `FFmpeg version | 8.1.1 | 6.1.0` da tabela do `README.md` (l.64) reforça a leitura: a versão paga (LGPL) embarca um FFmpeg próprio, completo; a GPL depende do FFmpegKit 6.1.x "enxuto".

Conclusão: "suportar todos os formatos de demux/decode" não é uma propriedade do código Swift (que é genérico), e sim do binário FFmpeg linkado — e o binário pinado por este fork foi compilado deliberadamente com whitelist por tamanho. A feature está **parcialmente** presente: os formatos mainstream (MKV/MP4/AVI/FLV/HLS + H.264/HEVC/VP9/AV1 + AAC/AC3/E-AC3/DTS/TrueHD/FLAC/Opus + ASS/PGS/SRT) funcionam, mas dezenas de demuxers/decoders existentes no FFmpeg completo não estão no binário.

Caminho para paridade (Infuse/versão paga): rebuildar o FFmpegKit removendo `--disable-demuxers`/`--disable-decoders` (ou trocando por `--enable-demuxers`/`--enable-decoders` completos) via o plugin `BuildFFmpeg` do repo kingslay/FFmpegKit e apontar o `Package.swift` deste fork para o binário custom — nenhuma mudança é necessária no Swift do player. Alternativa de confirmação empírica: logar `av_demuxer_iterate`/`av_codec_iterate` em runtime no app.
